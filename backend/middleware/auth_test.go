package middleware

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const testSecret = "test-secret-key-for-unit-tests"

func setupTestMiddleware(t *testing.T) {
	t.Helper()
	os.Setenv("JWT_SECRET", testSecret)
	t.Cleanup(func() { os.Unsetenv("JWT_SECRET") })
	gin.SetMode(gin.TestMode)
}

func createTestToken(userID string, expired bool) string {
	secret := testSecret
	if v := os.Getenv("JWT_SECRET"); v != "" {
		secret = v
	}

	var exp time.Time
	if expired {
		exp = time.Now().Add(-1 * time.Hour)
	} else {
		exp = time.Now().Add(24 * time.Hour)
	}

	claims := &Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(exp),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString([]byte(secret))
	return tokenString
}

func TestJWTAuthMiddleware_ValidToken(t *testing.T) {
	setupTestMiddleware(t)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/me", nil)
	c.Request.Header.Set("Authorization", "Bearer "+createTestToken("user123", false))

	JWTAuthMiddleware()(c)

	if c.GetString("userId") != "user123" {
		t.Errorf("expected userId=user123, got %s", c.GetString("userId"))
	}
	if c.IsAborted() {
		t.Error("expected request to NOT be aborted")
	}
}

func TestJWTAuthMiddleware_ExpiredToken(t *testing.T) {
	setupTestMiddleware(t)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/me", nil)
	c.Request.Header.Set("Authorization", "Bearer "+createTestToken("user123", true))

	JWTAuthMiddleware()(c)

	if c.GetString("userId") != "" {
		t.Error("expected empty userId for expired token")
	}
	if !c.IsAborted() {
		t.Error("expected request to be aborted")
	}
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestJWTAuthMiddleware_NoToken(t *testing.T) {
	setupTestMiddleware(t)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/me", nil)

	JWTAuthMiddleware()(c)

	if !c.IsAborted() {
		t.Error("expected request to be aborted")
	}
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestJWTAuthMiddleware_OptionsBypass(t *testing.T) {
	setupTestMiddleware(t)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("OPTIONS", "/api/me", nil)

	JWTAuthMiddleware()(c)

	if c.IsAborted() {
		t.Error("OPTIONS should bypass auth")
	}
}

func TestJWTAuthMiddleware_QueryParamToken(t *testing.T) {
	setupTestMiddleware(t)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/me?token="+createTestToken("queryuser", false), nil)

	JWTAuthMiddleware()(c)

	if c.GetString("userId") != "queryuser" {
		t.Errorf("expected userId=queryuser, got %s", c.GetString("userId"))
	}
}

func TestJWTAuthMiddleware_InvalidSignature(t *testing.T) {
	setupTestMiddleware(t)

	claims := &Claims{
		UserID: "user123",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString([]byte("wrong-secret"))

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest("GET", "/api/me", nil)
	c.Request.Header.Set("Authorization", "Bearer "+tokenString)

	JWTAuthMiddleware()(c)

	if !c.IsAborted() {
		t.Error("expected request to be aborted for wrong signature")
	}
}

func TestGetJWTSecret(t *testing.T) {
	os.Setenv("JWT_SECRET", "my-secret")
	t.Cleanup(func() { os.Unsetenv("JWT_SECRET") })

	secret := GetJWTSecret()
	if secret != "my-secret" {
		t.Errorf("expected 'my-secret', got '%s'", secret)
	}
}

func TestGetJWTSecret_Default(t *testing.T) {
	os.Unsetenv("JWT_SECRET")
	secret := GetJWTSecret()
	if secret == "" {
		t.Error("expected non-empty default secret")
	}
}
