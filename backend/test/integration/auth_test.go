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

	userRepo := repo.NewPgUserRepo(pool)
	rtRepo := repo.NewPgRefreshTokenRepo(pool)
	authSvc := service.NewAuthService(userRepo, rtRepo, "test-secret-that-is-long-enough-32ch!")

	ctx := context.Background()

	// Test: Register
	tokens, err := authSvc.Register(ctx, "chef@example.com", "password123", "Chef Test")
	if err != nil {
		t.Fatalf("Register failed: %v", err)
	}
	if tokens.AccessToken == "" {
		t.Error("Register: expected non-empty access token")
	}
	if tokens.RefreshToken == "" {
		t.Error("Register: expected non-empty refresh token")
	}

	// Test: Login
	loginTokens, err := authSvc.Login(ctx, "chef@example.com", "password123")
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if loginTokens.AccessToken == "" {
		t.Error("Login: expected non-empty access token")
	}
	if loginTokens.RefreshToken == "" {
		t.Error("Login: expected non-empty refresh token")
	}

	// Test: Refresh
	refreshTokens, err := authSvc.Refresh(ctx, loginTokens.RefreshToken)
	if err != nil {
		t.Fatalf("Refresh failed: %v", err)
	}
	if refreshTokens.AccessToken == "" {
		t.Error("Refresh: expected non-empty access token")
	}
	if refreshTokens.RefreshToken == "" {
		t.Error("Refresh: expected non-empty refresh token")
	}

	// Test: Duplicate register should fail
	_, err = authSvc.Register(ctx, "chef@example.com", "other", "Other")
	if err == nil {
		t.Error("expected error for duplicate registration, got nil")
	}

	// Test: Wrong password
	_, err = authSvc.Login(ctx, "chef@example.com", "wrongpassword")
	if err == nil {
		t.Error("expected error for wrong password, got nil")
	}
}
