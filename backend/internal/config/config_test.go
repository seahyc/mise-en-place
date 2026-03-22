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
