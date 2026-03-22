# Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Go backend skeleton with Postgres, auth, harness engineering (linting, structural tests, CI), and Docker Compose deployment — the foundation all other plans build on.

**Architecture:** Go server using Chi router, pgx for Postgres, golang-migrate for schema migrations, bcrypt + JWT for auth. Strict dependency layers (`types → config → repo → service → handler`) enforced by structural tests and golangci-lint. Docker Compose bundles Caddy + Go server + Postgres.

**Tech Stack:** Go 1.22+, Chi router, pgx, golang-migrate, golang-jwt/jwt, bcrypt, golangci-lint, lefthook, Docker Compose, Caddy, Postgres 16

**Spec:** `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md`

**Dependency:** None (this is the first plan)

---

### Task 1: Go Module + Project Skeleton

**Files:**
- Create: `backend/go.mod`
- Create: `backend/cmd/server/main.go`
- Create: `backend/internal/types/types.go`
- Create: `backend/internal/config/config.go`
- Create: `backend/internal/config/config_test.go`
- Create: `backend/AGENTS.md`

- [ ] **Step 1: Initialize Go module**

```bash
cd /Users/yingcong/Code/mise-en-place
mkdir -p backend/cmd/server backend/internal/types backend/internal/config
cd backend
go mod init github.com/yingcong/mise-en-place/backend
```

- [ ] **Step 2: Write AGENTS.md**

Create `backend/AGENTS.md`:
```markdown
# Mise en Place — Backend

## Build & Test
- `go build ./...` — build all packages
- `go test ./...` — run all tests
- `golangci-lint run` — lint

## Architecture
Go server with Chi router. Dependency layers (strict, enforced by structural tests):
`types → config → repo → service → handler`

Each layer can only import layers to its left. Handlers must not import repo directly.

## Conventions
- Table-driven tests with `t.Run`
- Errors: wrap with `fmt.Errorf("context: %w", err)`
- Structured logging via `slog`
- All external APIs behind interfaces for testability
```

- [ ] **Step 3: Write config with test (TDD)**

Create `backend/internal/config/config_test.go`:
```go
package config_test

import (
	"os"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/config"
)

func TestLoadFromEnv(t *testing.T) {
	os.Setenv("DATABASE_URL", "postgres://localhost:5432/mise")
	os.Setenv("JWT_SECRET", "test-secret-at-least-32-chars-long!!")
	os.Setenv("LISTEN_ADDR", ":9090")
	defer func() {
		os.Unsetenv("DATABASE_URL")
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("LISTEN_ADDR")
	}()

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.DatabaseURL != "postgres://localhost:5432/mise" {
		t.Errorf("got DatabaseURL=%q", cfg.DatabaseURL)
	}
	if cfg.JWTSecret != "test-secret-at-least-32-chars-long!!" {
		t.Errorf("got JWTSecret=%q", cfg.JWTSecret)
	}
	if cfg.ListenAddr != ":9090" {
		t.Errorf("got ListenAddr=%q", cfg.ListenAddr)
	}
}

func TestLoadMissingRequired(t *testing.T) {
	os.Unsetenv("DATABASE_URL")
	os.Unsetenv("JWT_SECRET")

	_, err := config.Load()
	if err == nil {
		t.Fatal("expected error for missing DATABASE_URL")
	}
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd backend && go test ./internal/config/ -v`
Expected: FAIL (config package doesn't exist yet)

- [ ] **Step 5: Implement config**

Create `backend/internal/config/config.go`:
```go
package config

import (
	"fmt"
	"os"
)

type Config struct {
	DatabaseURL string
	JWTSecret   string
	ListenAddr  string

	// External APIs (optional, loaded when needed)
	GroqAPIKey      string
	KimiAPIKey      string
	GLMAPIKey       string
	SiliconFlowKey  string
}

func Load() (*Config, error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	listenAddr := os.Getenv("LISTEN_ADDR")
	if listenAddr == "" {
		listenAddr = ":8080"
	}

	return &Config{
		DatabaseURL:    dbURL,
		JWTSecret:      jwtSecret,
		ListenAddr:     listenAddr,
		GroqAPIKey:     os.Getenv("GROQ_API_KEY"),
		KimiAPIKey:     os.Getenv("KIMI_API_KEY"),
		GLMAPIKey:      os.Getenv("GLM_API_KEY"),
		SiliconFlowKey: os.Getenv("SILICON_FLOW_KEY"),
	}, nil
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd backend && go test ./internal/config/ -v`
Expected: PASS

- [ ] **Step 7: Write minimal main.go**

Create `backend/cmd/server/main.go`:
```go
package main

import (
	"log/slog"
	"os"

	"github.com/yingcong/mise-en-place/backend/internal/config"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	slog.Info("server starting", "addr", cfg.ListenAddr)
}
```

- [ ] **Step 8: Write types package**

Create `backend/internal/types/types.go`:
```go
package types

import "time"

type UserID string
type RecipeID string
type SessionID string

type User struct {
	ID           UserID    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"display_name"`
	GoogleID     string    `json:"google_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type Recipe struct {
	ID          RecipeID    `json:"id"`
	Title       string      `json:"title"`
	Description string      `json:"description"`
	SourceURL   string      `json:"source_url,omitempty"`
	SourceType  string      `json:"source_type"`
	Cuisine     string      `json:"cuisine,omitempty"`
	ImageURL    string      `json:"image_url,omitempty"`
	UserID      UserID      `json:"user_id"`
	Ingredients []string    `json:"ingredients"`
	Steps       []RecipeStep `json:"steps"`
	CreatedAt   time.Time   `json:"created_at"`
	UpdatedAt   time.Time   `json:"updated_at"`
}

type RecipeStep struct {
	OrderIndex int    `json:"order_index"`
	Text       string `json:"text"`
	ImageURL   string `json:"image_url,omitempty"`
}

type SessionStatus string

const (
	SessionSetup      SessionStatus = "setup"
	SessionInProgress SessionStatus = "in_progress"
	SessionPaused     SessionStatus = "paused"
	SessionCompleted  SessionStatus = "completed"
)

type CookingSession struct {
	ID          SessionID     `json:"id"`
	UserID      UserID        `json:"user_id"`
	Status      SessionStatus `json:"status"`
	RecipeIDs   []RecipeID    `json:"recipe_ids"`
	Steps       []SessionStep `json:"steps"`
	CreatedAt   time.Time     `json:"created_at"`
	StartedAt   *time.Time    `json:"started_at,omitempty"`
	CompletedAt *time.Time    `json:"completed_at,omitempty"`
}

type SessionStep struct {
	ID            string     `json:"id"`
	OrderIndex    int        `json:"order_index"`
	Text          string     `json:"text"`
	SourceDishTag string     `json:"source_dish_tag,omitempty"`
	IsCompleted   bool       `json:"is_completed"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
	AgentNotes    string     `json:"agent_notes,omitempty"`
}

type JobType string
type JobStatus string

const (
	JobIngestVideo   JobType = "ingest_video"
	JobGenerateImages JobType = "generate_images"

	JobPending JobStatus = "pending"
	JobRunning JobStatus = "running"
	JobDone    JobStatus = "done"
	JobFailed  JobStatus = "failed"
)
```

- [ ] **Step 9: Verify build**

Run: `cd backend && go build ./...`
Expected: Success, no errors

- [ ] **Step 10: Commit**

```bash
git add backend/
git commit -m "feat(backend): initialize Go project skeleton with config, types, and AGENTS.md"
```

---

### Task 2: Database Migrations

**Files:**
- Create: `backend/migrations/001_initial_schema.up.sql`
- Create: `backend/migrations/001_initial_schema.down.sql`

- [ ] **Step 1: Create migrations directory**

```bash
mkdir -p backend/migrations
```

- [ ] **Step 2: Write up migration**

Create `backend/migrations/001_initial_schema.up.sql`:
```sql
-- Users & Auth
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL DEFAULT '',
    password_hash TEXT NOT NULL DEFAULT '',
    google_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

-- Recipes
CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    source_url TEXT,
    source_type TEXT NOT NULL DEFAULT 'manual',
    cuisine TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_recipes_user ON recipes(user_id);

CREATE TABLE recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INT NOT NULL DEFAULT 0,
    text TEXT NOT NULL
);
CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_id);

CREATE TABLE recipe_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INT NOT NULL,
    text TEXT NOT NULL,
    image_url TEXT
);
CREATE INDEX idx_recipe_steps_recipe ON recipe_steps(recipe_id);

-- Cooking Sessions
CREATE TABLE cooking_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'setup',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);
CREATE INDEX idx_sessions_user ON cooking_sessions(user_id);

CREATE TABLE session_recipes (
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, recipe_id)
);

CREATE TABLE session_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    order_index INT NOT NULL,
    text TEXT NOT NULL,
    source_dish_tag TEXT,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    completed_at TIMESTAMPTZ,
    agent_notes TEXT
);
CREATE INDEX idx_session_steps_session ON session_steps(session_id);

-- Voice Conversation History
CREATE TABLE conversation_turns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    tool_calls JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_conversation_turns_session ON conversation_turns(session_id);

-- Job Queue
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    payload JSONB NOT NULL DEFAULT '{}',
    result JSONB,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_user ON jobs(user_id);
```

- [ ] **Step 3: Write down migration**

Create `backend/migrations/001_initial_schema.down.sql`:
```sql
DROP TABLE IF EXISTS jobs;
DROP TABLE IF EXISTS conversation_turns;
DROP TABLE IF EXISTS session_steps;
DROP TABLE IF EXISTS session_recipes;
DROP TABLE IF EXISTS cooking_sessions;
DROP TABLE IF EXISTS recipe_steps;
DROP TABLE IF EXISTS recipe_ingredients;
DROP TABLE IF EXISTS recipes;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS users;
```

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/
git commit -m "feat(backend): add initial database schema migration"
```

---

### Task 3: Repository Layer (Postgres Queries)

**Files:**
- Create: `backend/internal/repo/db.go`
- Create: `backend/internal/repo/users.go`
- Create: `backend/internal/repo/users_test.go`

- [ ] **Step 1: Add pgx dependency**

```bash
cd backend
go get github.com/jackc/pgx/v5
go get github.com/jackc/pgx/v5/pgxpool
```

- [ ] **Step 2: Write db.go connection pool**

Create `backend/internal/repo/db.go`:
```go
package repo

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

func NewPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return pool, nil
}
```

- [ ] **Step 3: Write failing user repo test**

Create `backend/internal/repo/users_test.go`:
```go
package repo_test

import (
	"context"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Integration test — requires Postgres (via testcontainers in Task 5)
// For now, test the interface compiles and types are correct.

func TestUserRepoInterface(t *testing.T) {
	// Verify the interface is implementable
	var _ repo.UserRepo = (*repo.PgUserRepo)(nil)
}

func TestCreateUserArgs(t *testing.T) {
	args := repo.CreateUserArgs{
		Email:        "test@example.com",
		DisplayName:  "Test User",
		PasswordHash: "hashed",
	}
	if args.Email != "test@example.com" {
		t.Error("unexpected email")
	}
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd backend && go test ./internal/repo/ -v`
Expected: FAIL (types don't exist yet)

- [ ] **Step 5: Implement user repo**

Create `backend/internal/repo/users.go`:
```go
package repo

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

type CreateUserArgs struct {
	Email        string
	DisplayName  string
	PasswordHash string
	GoogleID     string
}

type UserRepo interface {
	Create(ctx context.Context, args CreateUserArgs) (*types.User, error)
	GetByID(ctx context.Context, id types.UserID) (*types.User, error)
	GetByEmail(ctx context.Context, email string) (*types.User, error)
	GetByGoogleID(ctx context.Context, googleID string) (*types.User, error)
}

type PgUserRepo struct {
	pool *pgxpool.Pool
}

func NewUserRepo(pool *pgxpool.Pool) *PgUserRepo {
	return &PgUserRepo{pool: pool}
}

func (r *PgUserRepo) Create(ctx context.Context, args CreateUserArgs) (*types.User, error) {
	var u types.User
	err := r.pool.QueryRow(ctx,
		`INSERT INTO users (email, display_name, password_hash, google_id)
		 VALUES ($1, $2, $3, NULLIF($4, ''))
		 RETURNING id, email, display_name, COALESCE(google_id, ''), created_at`,
		args.Email, args.DisplayName, args.PasswordHash, args.GoogleID,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.GoogleID, &u.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	return &u, nil
}

func (r *PgUserRepo) GetByID(ctx context.Context, id types.UserID) (*types.User, error) {
	return r.scanUser(ctx, "id = $1", string(id))
}

func (r *PgUserRepo) GetByEmail(ctx context.Context, email string) (*types.User, error) {
	return r.scanUser(ctx, "email = $1", email)
}

func (r *PgUserRepo) GetByGoogleID(ctx context.Context, googleID string) (*types.User, error) {
	return r.scanUser(ctx, "google_id = $1", googleID)
}

func (r *PgUserRepo) scanUser(ctx context.Context, where string, arg any) (*types.User, error) {
	var u types.User
	err := r.pool.QueryRow(ctx,
		`SELECT id, email, display_name, COALESCE(google_id, ''), created_at
		 FROM users WHERE `+where, arg,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.GoogleID, &u.CreatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return &u, nil
}

// RefreshToken repo

type RefreshTokenRepo interface {
	Create(ctx context.Context, userID types.UserID, tokenHash string, expiresAt time.Time) error
	GetByHash(ctx context.Context, tokenHash string) (userID types.UserID, expiresAt time.Time, err error)
	DeleteByHash(ctx context.Context, tokenHash string) error
	DeleteByUser(ctx context.Context, userID types.UserID) error
}

type PgRefreshTokenRepo struct {
	pool *pgxpool.Pool
}

func NewRefreshTokenRepo(pool *pgxpool.Pool) *PgRefreshTokenRepo {
	return &PgRefreshTokenRepo{pool: pool}
}

func (r *PgRefreshTokenRepo) Create(ctx context.Context, userID types.UserID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		string(userID), tokenHash, expiresAt,
	)
	return err
}

func (r *PgRefreshTokenRepo) GetByHash(ctx context.Context, tokenHash string) (types.UserID, time.Time, error) {
	var userID types.UserID
	var expiresAt time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT user_id, expires_at FROM refresh_tokens WHERE token_hash = $1`,
		tokenHash,
	).Scan(&userID, &expiresAt)
	return userID, expiresAt, err
}

func (r *PgRefreshTokenRepo) DeleteByHash(ctx context.Context, tokenHash string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE token_hash = $1`, tokenHash)
	return err
}

func (r *PgRefreshTokenRepo) DeleteByUser(ctx context.Context, userID types.UserID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM refresh_tokens WHERE user_id = $1`, string(userID))
	return err
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd backend && go test ./internal/repo/ -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add backend/internal/repo/ backend/go.mod backend/go.sum
git commit -m "feat(backend): add repo layer with user and refresh token queries"
```

---

### Task 4: Auth Service + JWT

**Files:**
- Create: `backend/internal/service/auth.go`
- Create: `backend/internal/service/auth_test.go`

- [ ] **Step 1: Add JWT dependency**

```bash
cd backend
go get github.com/golang-jwt/jwt/v5
go get golang.org/x/crypto/bcrypt
```

- [ ] **Step 2: Write failing auth test**

Create `backend/internal/service/auth_test.go`:
```go
package service_test

import (
	"context"
	"testing"
	"time"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Stub repos for unit testing (no DB needed)

type stubUserRepo struct {
	users map[string]*types.User
}

func newStubUserRepo() *stubUserRepo {
	return &stubUserRepo{users: make(map[string]*types.User)}
}

func (s *stubUserRepo) Create(_ context.Context, args interface{ GetEmail() string }) (*types.User, error) {
	// Simplified — real tests use the repo interface
	return nil, nil
}
func (s *stubUserRepo) GetByID(_ context.Context, id types.UserID) (*types.User, error) {
	return s.users[string(id)], nil
}
func (s *stubUserRepo) GetByEmail(_ context.Context, email string) (*types.User, error) {
	for _, u := range s.users {
		if u.Email == email {
			return u, nil
		}
	}
	return nil, nil
}
func (s *stubUserRepo) GetByGoogleID(_ context.Context, gid string) (*types.User, error) {
	return nil, nil
}

func TestHashAndVerifyPassword(t *testing.T) {
	hash, err := service.HashPassword("mysecretpassword")
	if err != nil {
		t.Fatalf("hash error: %v", err)
	}
	if !service.CheckPassword("mysecretpassword", hash) {
		t.Error("password should match")
	}
	if service.CheckPassword("wrong", hash) {
		t.Error("wrong password should not match")
	}
}

func TestGenerateAndParseJWT(t *testing.T) {
	secret := "test-secret-that-is-long-enough-32ch!"
	userID := types.UserID("user-123")

	token, err := service.GenerateAccessToken(userID, secret, time.Hour)
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}

	parsed, err := service.ParseAccessToken(token, secret)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if parsed != userID {
		t.Errorf("got userID=%q, want %q", parsed, userID)
	}
}

func TestParseExpiredJWT(t *testing.T) {
	secret := "test-secret-that-is-long-enough-32ch!"
	userID := types.UserID("user-123")

	token, _ := service.GenerateAccessToken(userID, secret, -time.Hour)
	_, err := service.ParseAccessToken(token, secret)
	if err == nil {
		t.Error("expected error for expired token")
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && go test ./internal/service/ -v`
Expected: FAIL

- [ ] **Step 4: Implement auth service**

Create `backend/internal/service/auth.go`:
```go
package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hash password: %w", err)
	}
	return string(hash), nil
}

func CheckPassword(password, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

func GenerateAccessToken(userID types.UserID, secret string, ttl time.Duration) (string, error) {
	claims := jwt.MapClaims{
		"sub": string(userID),
		"exp": time.Now().Add(ttl).Unix(),
		"iat": time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

func ParseAccessToken(tokenStr, secret string) (types.UserID, error) {
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(secret), nil
	})
	if err != nil {
		return "", fmt.Errorf("parse token: %w", err)
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", fmt.Errorf("invalid token")
	}
	sub, _ := claims.GetSubject()
	return types.UserID(sub), nil
}

func GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate refresh token: %w", err)
	}
	raw = hex.EncodeToString(b)
	h := sha256.Sum256([]byte(raw))
	hash = hex.EncodeToString(h[:])
	return raw, hash, nil
}

type AuthService struct {
	users         repo.UserRepo
	refreshTokens repo.RefreshTokenRepo
	jwtSecret     string
	accessTTL     time.Duration
	refreshTTL    time.Duration
}

func NewAuthService(users repo.UserRepo, rt repo.RefreshTokenRepo, jwtSecret string) *AuthService {
	return &AuthService{
		users:         users,
		refreshTokens: rt,
		jwtSecret:     jwtSecret,
		accessTTL:     time.Hour,
		refreshTTL:    30 * 24 * time.Hour,
	}
}

type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func (s *AuthService) Register(ctx context.Context, email, password, displayName string) (*TokenPair, error) {
	existing, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("check existing: %w", err)
	}
	if existing != nil {
		return nil, fmt.Errorf("email already registered")
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
		return nil, fmt.Errorf("create user: %w", err)
	}

	return s.issueTokens(ctx, user.ID)
}

func (s *AuthService) Login(ctx context.Context, email, password string) (*TokenPair, error) {
	user, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	if user == nil || !CheckPassword(password, user.PasswordHash) {
		return nil, fmt.Errorf("invalid credentials")
	}
	return s.issueTokens(ctx, user.ID)
}

func (s *AuthService) Refresh(ctx context.Context, rawToken string) (*TokenPair, error) {
	h := sha256.Sum256([]byte(rawToken))
	hash := hex.EncodeToString(h[:])

	userID, expiresAt, err := s.refreshTokens.GetByHash(ctx, hash)
	if err != nil {
		return nil, fmt.Errorf("invalid refresh token")
	}
	if time.Now().After(expiresAt) {
		return nil, fmt.Errorf("refresh token expired")
	}

	// Rotate: delete old, issue new
	_ = s.refreshTokens.DeleteByHash(ctx, hash)
	return s.issueTokens(ctx, userID)
}

func (s *AuthService) issueTokens(ctx context.Context, userID types.UserID) (*TokenPair, error) {
	accessToken, err := GenerateAccessToken(userID, s.jwtSecret, s.accessTTL)
	if err != nil {
		return nil, err
	}

	rawRefresh, hashRefresh, err := GenerateRefreshToken()
	if err != nil {
		return nil, err
	}

	if err := s.refreshTokens.Create(ctx, userID, hashRefresh, time.Now().Add(s.refreshTTL)); err != nil {
		return nil, fmt.Errorf("store refresh token: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: rawRefresh,
		ExpiresIn:    int(s.accessTTL.Seconds()),
	}, nil
}
```

**Google OAuth**: Add `GoogleLogin(ctx, googleIDToken string) (*TokenPair, error)` to AuthService. Verify the Google ID token by fetching Google's public keys from `https://www.googleapis.com/oauth2/v3/certs` and validating the JWT. Extract email + name from claims. Create or find user by `google_id`. Issue token pair. Add handler `POST /auth/google` with `{"id_token": "..."}`. Add dependency: `go get google.golang.org/api/idtoken`.

Note: The `types.User` struct needs a `PasswordHash` field. Update `backend/internal/types/types.go` — add `PasswordHash string` to the User struct (not in JSON output):
```go
type User struct {
	ID           UserID    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"display_name"`
	PasswordHash string    `json:"-"`
	GoogleID     string    `json:"google_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && go test ./internal/service/ -v`
Expected: PASS (at least the unit tests for hash/JWT)

- [ ] **Step 6: Commit**

```bash
git add backend/internal/service/ backend/internal/types/ backend/go.mod backend/go.sum
git commit -m "feat(backend): add auth service with JWT, bcrypt, and refresh token rotation"
```

---

### Task 5: Auth HTTP Handlers

**Files:**
- Create: `backend/internal/handler/auth.go`
- Create: `backend/internal/handler/auth_test.go`
- Create: `backend/internal/handler/middleware.go`

- [ ] **Step 1: Add Chi dependency**

```bash
cd backend
go get github.com/go-chi/chi/v5
```

- [ ] **Step 2: Write failing handler test**

Create `backend/internal/handler/auth_test.go`:
```go
package handler_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/handler"
)

func TestRegisterHandler_MissingFields(t *testing.T) {
	h := handler.NewAuthHandler(nil) // nil service — test validation only
	body := `{"email": ""}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.Register(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("got status %d, want 400", w.Code)
	}
}

func TestHealthCheck(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	handler.HealthCheck(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("got status %d, want 200", w.Code)
	}
	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["status"] != "ok" {
		t.Errorf("got status=%q", resp["status"])
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && go test ./internal/handler/ -v`
Expected: FAIL

- [ ] **Step 4: Implement auth handlers**

Create `backend/internal/handler/auth.go`:
```go
package handler

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/yingcong/mise-en-place/backend/internal/service"
)

func HealthCheck(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type AuthHandler struct {
	auth *service.AuthService
}

func NewAuthHandler(auth *service.AuthService) *AuthHandler {
	return &AuthHandler{auth: auth}
}

type registerRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.Email == "" || req.Password == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "email and password are required"})
		return
	}

	tokens, err := h.auth.Register(r.Context(), req.Email, req.Password, req.DisplayName)
	if err != nil {
		slog.Error("register failed", "error", err)
		writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, tokens)
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.Email == "" || req.Password == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "email and password are required"})
		return
	}

	tokens, err := h.auth.Login(r.Context(), req.Email, req.Password)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid credentials"})
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.RefreshToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "refresh_token required"})
		return
	}

	tokens, err := h.auth.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid refresh token"})
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
```

Create `backend/internal/handler/middleware.go`:
```go
package handler

import (
	"context"
	"net/http"
	"strings"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

type contextKey string

const userIDKey contextKey = "userID"

func AuthMiddleware(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			auth := r.Header.Get("Authorization")
			if !strings.HasPrefix(auth, "Bearer ") {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing token"})
				return
			}
			token := strings.TrimPrefix(auth, "Bearer ")
			userID, err := service.ParseAccessToken(token, jwtSecret)
			if err != nil {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"})
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func GetUserID(ctx context.Context) types.UserID {
	id, _ := ctx.Value(userIDKey).(types.UserID)
	return id
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && go test ./internal/handler/ -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/handler/ backend/go.mod backend/go.sum
git commit -m "feat(backend): add auth HTTP handlers with JWT middleware"
```

---

### Task 6: Wire Up Router + Main

**Files:**
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Wire up Chi router in main.go**

Update `backend/cmd/server/main.go`:
```go
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"github.com/yingcong/mise-en-place/backend/internal/config"
	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()
	pool, err := repo.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	// Repos
	userRepo := repo.NewUserRepo(pool)
	rtRepo := repo.NewRefreshTokenRepo(pool)

	// Services
	authSvc := service.NewAuthService(userRepo, rtRepo, cfg.JWTSecret)

	// Handlers
	authHandler := handler.NewAuthHandler(authSvc)

	// Router
	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(chimw.Recoverer)
	r.Use(slogMiddleware)

	r.Get("/health", handler.HealthCheck)

	r.Route("/auth", func(r chi.Router) {
		r.Post("/register", authHandler.Register)
		r.Post("/login", authHandler.Login)
		r.Post("/refresh", authHandler.Refresh)
	})

	// Protected routes (placeholder — other plans add endpoints here)
	r.Group(func(r chi.Router) {
		r.Use(handler.AuthMiddleware(cfg.JWTSecret))
		r.Get("/me", func(w http.ResponseWriter, r *http.Request) {
			uid := handler.GetUserID(r.Context())
			handler.WriteJSON(w, http.StatusOK, map[string]string{"user_id": string(uid)})
		})
	})

	// Graceful shutdown
	srv := &http.Server{Addr: cfg.ListenAddr, Handler: r}
	go func() {
		slog.Info("server listening", "addr", cfg.ListenAddr)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	slog.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	srv.Shutdown(shutdownCtx)
}

func slogMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", chimw.GetReqID(r.Context()),
		)
	})
}
```

Note: Export `writeJSON` as `WriteJSON` in `handler/auth.go` so `main.go` can use it, or add a small helper. Alternatively, keep the `/me` handler in its own file. The implementing agent should resolve this — the intent is clear.

- [ ] **Step 2: Verify build**

Run: `cd backend && go build ./cmd/server/`
Expected: Success

- [ ] **Step 3: Commit**

```bash
git add backend/cmd/server/main.go
git commit -m "feat(backend): wire up Chi router with auth routes and graceful shutdown"
```

---

### Task 7: Harness — Linting + Structural Tests

**Files:**
- Create: `backend/.golangci.yml`
- Create: `backend/test/architecture_test.go`
- Create: `backend/lefthook.yml`

- [ ] **Step 1: Write golangci-lint config**

Create `backend/.golangci.yml`:
```yaml
run:
  timeout: 2m

linters:
  enable:
    - govet
    - staticcheck
    - errcheck
    - gosimple
    - ineffassign
    - revive
    - gosec
    - bodyclose
    - noctx

linters-settings:
  revive:
    rules:
      - name: blank-imports
      - name: context-as-argument
      - name: dot-imports
      - name: error-return
      - name: error-strings
      - name: exported
      - name: increment-decrement
      - name: var-naming
      - name: package-comments
        disabled: true

issues:
  exclude-rules:
    - path: _test\.go
      linters:
        - errcheck
        - gosec
```

- [ ] **Step 2: Run lint to verify it works**

Run: `cd backend && golangci-lint run ./...`
Expected: Either PASS or specific fixable issues. Fix any issues found.

- [ ] **Step 3: Write architectural boundary test**

Create `backend/test/architecture_test.go`:
```go
package test

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const modulePrefix = "github.com/yingcong/mise-en-place/backend/internal/"

// Dependency rules: layer → forbidden imports
// types → cannot import config, repo, service, handler
// config → cannot import repo, service, handler
// repo → cannot import service, handler
// service → cannot import handler
// handler → can import anything (it's the top layer)

var forbidden = map[string][]string{
	"types":   {"config", "repo", "service", "handler"},
	"config":  {"repo", "service", "handler"},
	"repo":    {"service", "handler"},
	"service": {"handler"},
}

func TestDependencyLayers(t *testing.T) {
	root := filepath.Join("..", "internal")

	for layer, blocked := range forbidden {
		layerDir := filepath.Join(root, layer)
		if _, err := os.Stat(layerDir); os.IsNotExist(err) {
			continue
		}

		fset := token.NewFileSet()
		pkgs, err := parser.ParseDir(fset, layerDir, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatalf("parse %s: %v", layer, err)
		}

		for _, pkg := range pkgs {
			for filename, file := range pkg.Files {
				for _, imp := range file.Imports {
					path := strings.Trim(imp.Path.Value, `"`)
					for _, b := range blocked {
						if strings.HasPrefix(path, modulePrefix+b) {
							t.Errorf("%s imports %s — %s must not import %s layer\n"+
								"  Fix: inject via interface in service layer. See AGENTS.md",
								filepath.Base(filename), path, layer, b)
						}
					}
				}
			}
		}
	}
}
```

- [ ] **Step 4: Run structural test**

Run: `cd backend && go test ./test/ -v -run TestDependencyLayers`
Expected: PASS (current code should respect layers)

- [ ] **Step 5: Write lefthook config**

Create `backend/lefthook.yml`:
```yaml
pre-commit:
  parallel: true
  commands:
    lint:
      run: cd backend && golangci-lint run ./...
    test:
      run: cd backend && go test ./... -short -count=1
    build:
      run: cd backend && go build ./...
```

- [ ] **Step 6: Commit**

```bash
git add backend/.golangci.yml backend/test/ backend/lefthook.yml
git commit -m "feat(backend): add golangci-lint config, architectural boundary tests, and pre-commit hooks"
```

---

### Task 8: Docker Compose + Caddy

**Files:**
- Create: `backend/Dockerfile`
- Create: `backend/docker-compose.yml`
- Create: `backend/Caddyfile`
- Create: `backend/.env.example`

- [ ] **Step 1: Write Dockerfile**

Create `backend/Dockerfile`:
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /server /server
COPY migrations/ /migrations/
EXPOSE 8080
CMD ["/server"]
```

- [ ] **Step 2: Write docker-compose.yml**

Create `backend/docker-compose.yml`:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: mise
      POSTGRES_USER: mise
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-mise-dev}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mise"]
      interval: 5s
      timeout: 3s
      retries: 5

  migrate:
    image: migrate/migrate
    volumes:
      - ./migrations:/migrations
    command: ["-path", "/migrations", "-database", "postgres://mise:${POSTGRES_PASSWORD:-mise-dev}@postgres:5432/mise?sslmode=disable", "up"]
    depends_on:
      postgres:
        condition: service_healthy

  server:
    build: .
    environment:
      DATABASE_URL: postgres://mise:${POSTGRES_PASSWORD:-mise-dev}@postgres:5432/mise?sslmode=disable
      JWT_SECRET: ${JWT_SECRET}
      LISTEN_ADDR: ":8080"
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      KIMI_API_KEY: ${KIMI_API_KEY:-}
      GLM_API_KEY: ${GLM_API_KEY:-}
      SILICON_FLOW_KEY: ${SILICON_FLOW_KEY:-}
    ports:
      - "8080:8080"
    depends_on:
      migrate:
        condition: service_completed_successfully

  kokoro:
    image: ghcr.io/remsky/kokoro-fastapi:latest
    ports:
      - "8880:8880"
    volumes:
      - kokoro_models:/app/models
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8880/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - image_data:/data/images
    depends_on:
      - server

volumes:
  pgdata:
  caddy_data:
  caddy_config:
  image_data:
  kokoro_models:
```

- [ ] **Step 3: Write Caddyfile**

Create `backend/Caddyfile`:
```
{
	# For local dev, use :80. For production, replace with your domain.
	# api.mise.seahyingcong.com
}

:80 {
	reverse_proxy server:8080

	handle_path /images/* {
		root * /data/images
		file_server
	}
}
```

- [ ] **Step 4: Write .env.example**

Create `backend/.env.example`:
```bash
# Required
POSTGRES_PASSWORD=change-me-in-production
JWT_SECRET=change-me-must-be-at-least-32-characters

# External APIs (optional — features degrade gracefully without them)
GROQ_API_KEY=
KIMI_API_KEY=
GLM_API_KEY=
SILICON_FLOW_KEY=
```

- [ ] **Step 5: Verify Docker build (if Docker available)**

Run: `cd backend && docker compose build server`
Expected: Success

- [ ] **Step 6: Commit**

```bash
git add backend/Dockerfile backend/docker-compose.yml backend/Caddyfile backend/.env.example
git commit -m "feat(backend): add Docker Compose with Caddy, Postgres, and migrations"
```

---

### Task 9: Integration Test Infrastructure

**Files:**
- Create: `backend/test/integration/helpers.go`
- Create: `backend/test/integration/auth_test.go`

- [ ] **Step 1: Add testcontainers dependency**

```bash
cd backend
go get github.com/testcontainers/testcontainers-go
go get github.com/testcontainers/testcontainers-go/modules/postgres
go get github.com/golang-migrate/migrate/v4
go get github.com/golang-migrate/migrate/v4/database/pgx/v5
go get github.com/golang-migrate/migrate/v4/source/file
```

- [ ] **Step 2: Write test helpers**

Create `backend/test/integration/helpers.go`:
```go
package integration

import (
	"context"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func SetupTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	t.Helper()
	ctx := context.Background()

	container, err := tcpostgres.Run(ctx, "postgres:16-alpine",
		tcpostgres.WithDatabase("mise_test"),
		tcpostgres.WithUsername("test"),
		tcpostgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).WithStartupTimeout(30*time.Second)),
	)
	if err != nil {
		t.Fatalf("start postgres container: %v", err)
	}

	connStr, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("get connection string: %v", err)
	}

	// Run migrations
	_, thisFile, _, _ := runtime.Caller(0)
	migrationsDir := filepath.Join(filepath.Dir(thisFile), "..", "..", "migrations")
	m, err := migrate.New("file://"+migrationsDir, "pgx5://"+connStr[len("postgres://"):])
	if err != nil {
		t.Fatalf("create migrator: %v", err)
	}
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		t.Fatalf("run migrations: %v", err)
	}

	pool, err := pgxpool.New(ctx, connStr)
	if err != nil {
		t.Fatalf("create pool: %v", err)
	}

	cleanup := func() {
		pool.Close()
		container.Terminate(ctx)
	}
	return pool, cleanup
}
```

- [ ] **Step 3: Write integration auth test**

Create `backend/test/integration/auth_test.go`:
```go
package integration

import (
	"context"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
)

func TestAuthFlow_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	pool, cleanup := SetupTestDB(t)
	defer cleanup()

	userRepo := repo.NewUserRepo(pool)
	rtRepo := repo.NewRefreshTokenRepo(pool)
	authSvc := service.NewAuthService(userRepo, rtRepo, "test-secret-that-is-long-enough-32ch!")

	ctx := context.Background()

	// Register
	tokens, err := authSvc.Register(ctx, "chef@example.com", "password123", "Chef Test")
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	if tokens.AccessToken == "" {
		t.Error("expected access token")
	}
	if tokens.RefreshToken == "" {
		t.Error("expected refresh token")
	}

	// Login
	loginTokens, err := authSvc.Login(ctx, "chef@example.com", "password123")
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if loginTokens.AccessToken == "" {
		t.Error("expected access token from login")
	}

	// Refresh
	refreshTokens, err := authSvc.Refresh(ctx, loginTokens.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if refreshTokens.AccessToken == "" {
		t.Error("expected new access token")
	}

	// Duplicate register should fail
	_, err = authSvc.Register(ctx, "chef@example.com", "other", "Other")
	if err == nil {
		t.Error("expected duplicate email error")
	}

	// Wrong password
	_, err = authSvc.Login(ctx, "chef@example.com", "wrongpassword")
	if err == nil {
		t.Error("expected invalid credentials error")
	}
}
```

- [ ] **Step 4: Run integration test**

Run: `cd backend && go test ./test/integration/ -v -count=1`
Expected: PASS (requires Docker running locally)

- [ ] **Step 5: Commit**

```bash
git add backend/test/integration/ backend/go.mod backend/go.sum
git commit -m "feat(backend): add integration test infra with testcontainers-go"
```

---

---

### Task 10: CI Pipeline (GitHub Actions)

**Files:**
- Create: `backend/.github/workflows/ci.yml`

- [ ] **Step 1: Write CI workflow**

Create `.github/workflows/ci.yml` (at repo root, not backend/):
```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  backend-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - uses: golangci/golangci-lint-action@v4
        with: { working-directory: backend }

  backend-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - run: cd backend && go test ./... -short -count=1

  backend-integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: mise_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports: ['5432:5432']
        options: --health-cmd pg_isready --health-interval 5s --health-timeout 3s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - run: cd backend && go test ./test/integration/ -v -count=1
        env:
          DATABASE_URL: postgres://test:test@localhost:5432/mise_test?sslmode=disable

  flutter-analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x' }
      - run: cd app_v2 && flutter pub get && flutter analyze

  flutter-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x' }
      - run: cd app_v2 && flutter pub get && flutter test

  architecture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - run: cd backend && go test ./test/ -v -run TestDependencyLayers
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions pipeline for backend + Flutter"
```

---

## Dependency Graph

```
Task 1 (skeleton) → Task 2 (migrations) → Task 3 (repo) → Task 4 (auth service)
                                                          → Task 5 (handlers) → Task 6 (wire up)
Task 7 (harness) can run after Task 1
Task 8 (docker) can run after Task 2
Task 9 (integration tests) requires Tasks 1-4
```

**Parallelizable**: Tasks 7 and 8 can run in parallel with Tasks 3-6.
