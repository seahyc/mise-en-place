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
	GroqAPIKey     string
	KimiAPIKey     string
	GLMAPIKey      string
	SiliconFlowKey string
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
