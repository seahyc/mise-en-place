package service

import (
	"testing"
	"time"
)

func TestHashAndVerifyPassword(t *testing.T) {
	hash, err := HashPassword("mysecretpassword")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}

	if !CheckPassword("mysecretpassword", hash) {
		t.Fatal("CheckPassword should return true for correct password")
	}

	if CheckPassword("wrong", hash) {
		t.Fatal("CheckPassword should return false for wrong password")
	}
}

func TestGenerateAndParseJWT(t *testing.T) {
	secret := "test-secret-key"
	userID := "user-123"

	token, err := GenerateAccessToken("user-123", secret, time.Hour)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}

	got, err := ParseAccessToken(token, secret)
	if err != nil {
		t.Fatalf("ParseAccessToken: %v", err)
	}

	if string(got) != userID {
		t.Fatalf("expected userID %q, got %q", userID, got)
	}
}

func TestParseExpiredJWT(t *testing.T) {
	secret := "test-secret-key"

	token, err := GenerateAccessToken("user-123", secret, -time.Hour)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}

	_, err = ParseAccessToken(token, secret)
	if err == nil {
		t.Fatal("ParseAccessToken should return error for expired token")
	}
}
