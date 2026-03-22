package repo_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
)

// TestUserRepoInterface verifies PgUserRepo satisfies UserRepo at compile time.
func TestUserRepoInterface(t *testing.T) {
	var _ repo.UserRepo = (*repo.PgUserRepo)(nil)
}

// TestRefreshTokenRepoInterface verifies PgRefreshTokenRepo satisfies RefreshTokenRepo at compile time.
func TestRefreshTokenRepoInterface(t *testing.T) {
	var _ repo.RefreshTokenRepo = (*repo.PgRefreshTokenRepo)(nil)
}

// TestCreateUserArgsFields verifies the CreateUserArgs struct has the expected fields.
func TestCreateUserArgsFields(t *testing.T) {
	args := repo.CreateUserArgs{
		Email:        "test@example.com",
		DisplayName:  "Test User",
		PasswordHash: "hash123",
		GoogleID:     "google123",
	}

	if args.Email != "test@example.com" {
		t.Errorf("Email = %q, want %q", args.Email, "test@example.com")
	}
	if args.DisplayName != "Test User" {
		t.Errorf("DisplayName = %q, want %q", args.DisplayName, "Test User")
	}
	if args.PasswordHash != "hash123" {
		t.Errorf("PasswordHash = %q, want %q", args.PasswordHash, "hash123")
	}
	if args.GoogleID != "google123" {
		t.Errorf("GoogleID = %q, want %q", args.GoogleID, "google123")
	}
}
