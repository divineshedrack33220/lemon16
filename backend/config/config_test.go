package config

import (
	"os"
	"testing"
)

func TestLoad_DefaultValues(t *testing.T) {
	os.Unsetenv("JWT_SECRET")
	os.Unsetenv("MONGODB_URI")
	os.Unsetenv("PORT")
	os.Setenv("GIN_MODE", "debug")
	os.Unsetenv("RENDER")
	os.Unsetenv("ALLOWED_ORIGINS")
	t.Cleanup(func() { os.Unsetenv("GIN_MODE") })

	cfg := Load()

	if cfg.MongoURI != "mongodb://localhost:27017" {
		t.Errorf("expected default MongoURI, got %s", cfg.MongoURI)
	}
	if cfg.DatabaseName != "coded" {
		t.Errorf("expected 'coded', got %s", cfg.DatabaseName)
	}
	if cfg.Port != "8080" {
		t.Errorf("expected '8080', got %s", cfg.Port)
	}
	if cfg.GinMode != "debug" {
		t.Errorf("expected 'debug', got %s", cfg.GinMode)
	}
	if cfg.IsRender {
		t.Error("expected IsRender=false")
	}
	if cfg.JWTSecret != "dev-secret-change-in-prod" {
		t.Errorf("expected default JWT secret, got %s", cfg.JWTSecret)
	}
}

func TestLoad_CustomEnvVars(t *testing.T) {
	os.Setenv("JWT_SECRET", "my-secret")
	os.Setenv("MONGODB_URI", "mongodb://custom:27017")
	os.Setenv("PORT", "9090")
	os.Setenv("GIN_MODE", "debug")
	t.Cleanup(func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("MONGODB_URI")
		os.Unsetenv("PORT")
		os.Unsetenv("GIN_MODE")
	})

	cfg := Load()

	if cfg.JWTSecret != "my-secret" {
		t.Errorf("expected 'my-secret', got %s", cfg.JWTSecret)
	}
	if cfg.MongoURI != "mongodb://custom:27017" {
		t.Errorf("expected custom MongoURI, got %s", cfg.MongoURI)
	}
	if cfg.Port != "9090" {
		t.Errorf("expected '9090', got %s", cfg.Port)
	}
	if cfg.GinMode != "debug" {
		t.Errorf("expected 'debug', got %s", cfg.GinMode)
	}
}

func TestLoad_AllowedOrigins(t *testing.T) {
	os.Setenv("JWT_SECRET", "test")
	os.Setenv("GIN_MODE", "debug")
	os.Setenv("ALLOWED_ORIGINS", "http://localhost:3000,https://example.com")
	t.Cleanup(func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("GIN_MODE")
		os.Unsetenv("ALLOWED_ORIGINS")
	})

	cfg := Load()

	if len(cfg.AllowedOrigins) != 2 {
		t.Errorf("expected 2 origins, got %d", len(cfg.AllowedOrigins))
	}
	if cfg.AllowedOrigins[0] != "http://localhost:3000" {
		t.Errorf("unexpected first origin: %s", cfg.AllowedOrigins[0])
	}
}

func TestLoad_IsRender(t *testing.T) {
	os.Setenv("JWT_SECRET", "test")
	os.Setenv("GIN_MODE", "debug")
	os.Setenv("RENDER", "true")
	t.Cleanup(func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("GIN_MODE")
		os.Unsetenv("RENDER")
	})

	cfg := Load()
	if !cfg.IsRender {
		t.Error("expected IsRender=true when RENDER env is set")
	}
}

func TestGetEnvDefault(t *testing.T) {
	os.Unsetenv("TEST_KEY")
	if v := getEnvDefault("TEST_KEY", "default"); v != "default" {
		t.Errorf("expected 'default', got '%s'", v)
	}

	os.Setenv("TEST_KEY", "actual")
	t.Cleanup(func() { os.Unsetenv("TEST_KEY") })
	if v := getEnvDefault("TEST_KEY", "default"); v != "actual" {
		t.Errorf("expected 'actual', got '%s'", v)
	}
}
