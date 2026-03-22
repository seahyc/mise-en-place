package repo

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// CreateUserArgs holds the arguments for creating a new user.
type CreateUserArgs struct {
	Email        string
	DisplayName  string
	PasswordHash string
	GoogleID     string
}

// UserRepo defines the interface for user persistence operations.
type UserRepo interface {
	Create(ctx context.Context, args CreateUserArgs) (*types.User, error)
	GetByID(ctx context.Context, id types.UserID) (*types.User, error)
	GetByEmail(ctx context.Context, email string) (*types.User, error)
	GetByGoogleID(ctx context.Context, googleID string) (*types.User, error)
}

// PgUserRepo implements UserRepo using PostgreSQL.
type PgUserRepo struct {
	pool *pgxpool.Pool
}

// NewPgUserRepo creates a new PgUserRepo.
func NewPgUserRepo(pool *pgxpool.Pool) *PgUserRepo {
	return &PgUserRepo{pool: pool}
}

// Create inserts a new user and returns the created user.
func (r *PgUserRepo) Create(ctx context.Context, args CreateUserArgs) (*types.User, error) {
	var u types.User
	err := r.pool.QueryRow(ctx,
		`INSERT INTO users (email, display_name, password_hash, google_id)
		 VALUES ($1, $2, $3, NULLIF($4, ''))
		 RETURNING id, email, display_name, password_hash, COALESCE(google_id, ''), created_at`,
		args.Email, args.DisplayName, args.PasswordHash, args.GoogleID,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.PasswordHash, &u.GoogleID, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// GetByID retrieves a user by their ID. Returns nil if not found.
func (r *PgUserRepo) GetByID(ctx context.Context, id types.UserID) (*types.User, error) {
	return r.getUser(ctx,
		`SELECT id, email, display_name, password_hash, COALESCE(google_id, ''), created_at
		 FROM users WHERE id = $1`, id)
}

// GetByEmail retrieves a user by email. Returns nil if not found.
func (r *PgUserRepo) GetByEmail(ctx context.Context, email string) (*types.User, error) {
	return r.getUser(ctx,
		`SELECT id, email, display_name, password_hash, COALESCE(google_id, ''), created_at
		 FROM users WHERE email = $1`, email)
}

// GetByGoogleID retrieves a user by Google ID. Returns nil if not found.
func (r *PgUserRepo) GetByGoogleID(ctx context.Context, googleID string) (*types.User, error) {
	return r.getUser(ctx,
		`SELECT id, email, display_name, password_hash, COALESCE(google_id, ''), created_at
		 FROM users WHERE google_id = $1`, googleID)
}

// getUser is a shared helper that executes a query and scans a single user row.
func (r *PgUserRepo) getUser(ctx context.Context, query string, args ...any) (*types.User, error) {
	var u types.User
	err := r.pool.QueryRow(ctx, query, args...).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.PasswordHash, &u.GoogleID, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// RefreshTokenRepo defines the interface for refresh token persistence.
type RefreshTokenRepo interface {
	Create(ctx context.Context, userID types.UserID, tokenHash string, expiresAt time.Time) error
	GetByHash(ctx context.Context, tokenHash string) (userID types.UserID, expiresAt time.Time, err error)
	DeleteByHash(ctx context.Context, tokenHash string) error
	DeleteByUser(ctx context.Context, userID types.UserID) error
}

// PgRefreshTokenRepo implements RefreshTokenRepo using PostgreSQL.
type PgRefreshTokenRepo struct {
	pool *pgxpool.Pool
}

// NewPgRefreshTokenRepo creates a new PgRefreshTokenRepo.
func NewPgRefreshTokenRepo(pool *pgxpool.Pool) *PgRefreshTokenRepo {
	return &PgRefreshTokenRepo{pool: pool}
}

// Create inserts a new refresh token.
func (r *PgRefreshTokenRepo) Create(ctx context.Context, userID types.UserID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)`,
		userID, tokenHash, expiresAt,
	)
	return err
}

// GetByHash retrieves a refresh token by its hash.
func (r *PgRefreshTokenRepo) GetByHash(ctx context.Context, tokenHash string) (types.UserID, time.Time, error) {
	var userID types.UserID
	var expiresAt time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT user_id, expires_at FROM refresh_tokens WHERE token_hash = $1`,
		tokenHash,
	).Scan(&userID, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", time.Time{}, nil
	}
	if err != nil {
		return "", time.Time{}, err
	}
	return userID, expiresAt, nil
}

// DeleteByHash deletes a refresh token by its hash.
func (r *PgRefreshTokenRepo) DeleteByHash(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM refresh_tokens WHERE token_hash = $1`,
		tokenHash,
	)
	return err
}

// DeleteByUser deletes all refresh tokens for a user.
func (r *PgRefreshTokenRepo) DeleteByUser(ctx context.Context, userID types.UserID) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM refresh_tokens WHERE user_id = $1`,
		userID,
	)
	return err
}
