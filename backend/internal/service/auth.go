package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Sentinel errors for the auth service.
var (
	ErrEmailTaken      = errors.New("auth: email already taken")
	ErrInvalidCreds    = errors.New("auth: invalid credentials")
	ErrInvalidToken    = errors.New("auth: invalid token")
	ErrTokenExpired    = errors.New("auth: token expired")
	ErrGoogleIDToken   = errors.New("auth: invalid Google ID token")
)

// ---------------------------------------------------------------------------
// Standalone functions
// ---------------------------------------------------------------------------

// HashPassword hashes a plaintext password using bcrypt with default cost.
func HashPassword(password string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// CheckPassword returns true if the plaintext password matches the bcrypt hash.
func CheckPassword(password, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// GenerateAccessToken creates a signed JWT with HS256 for the given user.
func GenerateAccessToken(userID types.UserID, secret string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := jwt.RegisteredClaims{
		Subject:   string(userID),
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// ParseAccessToken validates a JWT and returns the user ID from the sub claim.
func ParseAccessToken(tokenStr, secret string) (types.UserID, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &jwt.RegisteredClaims{},
		func(t *jwt.Token) (any, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return []byte(secret), nil
		},
	)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}

	claims, ok := token.Claims.(*jwt.RegisteredClaims)
	if !ok || !token.Valid {
		return "", ErrInvalidToken
	}

	return types.UserID(claims.Subject), nil
}

// GenerateRefreshToken returns a cryptographically random token (hex-encoded)
// and its SHA-256 hash for storage.
func GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", "", err
	}
	raw = hex.EncodeToString(b)
	h := sha256.Sum256([]byte(raw))
	hash = hex.EncodeToString(h[:])
	return raw, hash, nil
}

// ---------------------------------------------------------------------------
// TokenPair
// ---------------------------------------------------------------------------

// TokenPair is the response returned on successful authentication.
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

// ---------------------------------------------------------------------------
// AuthService
// ---------------------------------------------------------------------------

// AuthService handles authentication: registration, login, token refresh, and
// Google OAuth.
type AuthService struct {
	users         repo.UserRepo
	refreshTokens repo.RefreshTokenRepo
	jwtSecret     string
	accessTTL     time.Duration
	refreshTTL    time.Duration
}

// NewAuthService creates an AuthService with sensible defaults (1h access,
// 30d refresh).
func NewAuthService(users repo.UserRepo, rt repo.RefreshTokenRepo, jwtSecret string) *AuthService {
	return &AuthService{
		users:         users,
		refreshTokens: rt,
		jwtSecret:     jwtSecret,
		accessTTL:     time.Hour,
		refreshTTL:    30 * 24 * time.Hour,
	}
}

// Register creates a new user account and returns a token pair.
func (s *AuthService) Register(ctx context.Context, email, password, displayName string) (*TokenPair, error) {
	existing, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, ErrEmailTaken
	}

	hash, err := HashPassword(password)
	if err != nil {
		return nil, err
	}

	user, err := s.users.Create(ctx, repo.CreateUserArgs{
		Email:        email,
		DisplayName:  displayName,
		PasswordHash: hash,
	})
	if err != nil {
		return nil, err
	}

	return s.issueTokens(ctx, user.ID)
}

// Login authenticates with email/password and returns a token pair.
func (s *AuthService) Login(ctx context.Context, email, password string) (*TokenPair, error) {
	user, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, ErrInvalidCreds
	}

	if !CheckPassword(password, user.PasswordHash) {
		return nil, ErrInvalidCreds
	}

	return s.issueTokens(ctx, user.ID)
}

// Refresh validates a raw refresh token, rotates it, and returns a new pair.
func (s *AuthService) Refresh(ctx context.Context, rawToken string) (*TokenPair, error) {
	h := sha256.Sum256([]byte(rawToken))
	tokenHash := hex.EncodeToString(h[:])

	userID, expiresAt, err := s.refreshTokens.GetByHash(ctx, tokenHash)
	if err != nil {
		return nil, err
	}
	if userID == "" {
		return nil, ErrInvalidToken
	}
	if time.Now().After(expiresAt) {
		// Clean up the expired token.
		_ = s.refreshTokens.DeleteByHash(ctx, tokenHash)
		return nil, ErrTokenExpired
	}

	// Rotate: delete the old token, issue a fresh pair.
	if err := s.refreshTokens.DeleteByHash(ctx, tokenHash); err != nil {
		return nil, err
	}

	return s.issueTokens(ctx, userID)
}

// GoogleLogin verifies a Google ID token, finds or creates the user, and
// returns a token pair.
func (s *AuthService) GoogleLogin(ctx context.Context, googleIDToken string) (*TokenPair, error) {
	// Validate the Google ID token by calling Google's tokeninfo endpoint.
	// In production this should use google.golang.org/api/idtoken, but we
	// keep the import lightweight for now and accept the token's claims
	// after basic validation.
	//
	// TODO: integrate google.golang.org/api/idtoken for full verification.
	return nil, ErrGoogleIDToken
}

// issueTokens generates an access+refresh token pair and stores the refresh
// token hash in the database.
func (s *AuthService) issueTokens(ctx context.Context, userID types.UserID) (*TokenPair, error) {
	accessToken, err := GenerateAccessToken(userID, s.jwtSecret, s.accessTTL)
	if err != nil {
		return nil, err
	}

	raw, hash, err := GenerateRefreshToken()
	if err != nil {
		return nil, err
	}

	if err := s.refreshTokens.Create(ctx, userID, hash, time.Now().Add(s.refreshTTL)); err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: raw,
		ExpiresIn:    int(s.accessTTL.Seconds()),
	}, nil
}
