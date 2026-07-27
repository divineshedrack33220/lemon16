package config

import (
	"log/slog"
	"os"
	"strings"
)

type Config struct {
	JWTSecret          string
	MongoURI           string
	DatabaseName       string
	Port               string
	GinMode            string
	IsRender           bool
	AllowedOrigins     []string
	CloudinaryURL      string
	VAPIDPublicKey     string
	VAPIDPrivateKey    string
	GoogleClientID     string
	GoogleClientSecret string
	GoogleRedirectURL  string
	ReferralBaseURL    string
}

func Load() *Config {
	cfg := &Config{
		JWTSecret:          os.Getenv("JWT_SECRET"),
		MongoURI:           os.Getenv("MONGODB_URI"),
		DatabaseName:       "coded",
		Port:               getEnvDefault("PORT", "8080"),
		GinMode:            getEnvDefault("GIN_MODE", "release"),
		IsRender:           os.Getenv("RENDER") != "",
		CloudinaryURL:      os.Getenv("CLOUDINARY_URL"),
		VAPIDPublicKey:     os.Getenv("VAPID_PUBLIC_KEY"),
		VAPIDPrivateKey:    os.Getenv("VAPID_PRIVATE_KEY"),
		GoogleClientID:     os.Getenv("GOOGLE_CLIENT_ID"),
		GoogleClientSecret: os.Getenv("GOOGLE_CLIENT_SECRET"),
		GoogleRedirectURL:  getEnvDefault("GOOGLE_REDIRECT_URL", "https://coded-backend.onrender.com/api/google/callback"),
		ReferralBaseURL:    "https://zukaping.app",
	}

	if cfg.MongoURI == "" {
		cfg.MongoURI = "mongodb://localhost:27017"
		slog.Info("no MONGODB_URI set, using localhost")
	}

	if cfg.JWTSecret == "" {
		if cfg.GinMode == "release" {
			slog.Error("JWT_SECRET is required in release mode")
			os.Exit(1)
		}
		cfg.JWTSecret = "dev-secret-change-in-prod"
		slog.Warn("using insecure default JWT_SECRET (development only)")
	}

	if envOrigins := os.Getenv("ALLOWED_ORIGINS"); envOrigins != "" {
		cfg.AllowedOrigins = strings.Split(envOrigins, ",")
	} else if cfg.GinMode == "debug" {
		cfg.AllowedOrigins = []string{"*"}
		slog.Info("no ALLOWED_ORIGINS set, allowing all origins in debug mode")
	}

	return cfg
}

func getEnvDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
