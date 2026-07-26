package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestRateLimiter_AllowsUnderLimit(t *testing.T) {
	rl := NewIPRateLimiter(5, time.Minute)
	for i := 0; i < 5; i++ {
		if !rl.Allow("1.2.3.4") {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
}

func TestRateLimiter_RejectsOverLimit(t *testing.T) {
	rl := NewIPRateLimiter(3, time.Minute)
	for i := 0; i < 3; i++ {
		rl.Allow("1.2.3.4")
	}
	if rl.Allow("1.2.3.4") {
		t.Error("4th request should be rejected")
	}
}

func TestRateLimiter_DifferentIPs(t *testing.T) {
	rl := NewIPRateLimiter(1, time.Minute)
	if !rl.Allow("1.1.1.1") {
		t.Error("first IP should be allowed")
	}
	if rl.Allow("1.1.1.1") {
		t.Error("same IP should be rejected")
	}
	if !rl.Allow("2.2.2.2") {
		t.Error("different IP should be allowed")
	}
}

func TestRateLimiter_WindowExpiry(t *testing.T) {
	rl := NewIPRateLimiter(1, 10*time.Millisecond)
	rl.Allow("1.2.3.4")
	if rl.Allow("1.2.3.4") {
		t.Error("should be rejected within window")
	}
	time.Sleep(15 * time.Millisecond)
	if !rl.Allow("1.2.3.4") {
		t.Error("should be allowed after window expires")
	}
}

func TestRateLimiter_Eviction(t *testing.T) {
	rl := NewIPRateLimiter(1, 10*time.Millisecond)
	rl.Allow("1.2.3.4")
	if rl.ActiveIPs() != 1 {
		t.Errorf("expected 1 active IP, got %d", rl.ActiveIPs())
	}
	time.Sleep(15 * time.Millisecond)
	// Trigger eviction via Allow call
	rl.Allow("5.6.7.8")
	// After eviction, old IP should be gone
	if rl.ActiveIPs() != 1 {
		t.Errorf("expected 1 active IP after eviction, got %d", rl.ActiveIPs())
	}
}

func TestRateLimitMiddleware_BlocksOverLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := NewIPRateLimiter(2, time.Minute)
	middleware := RateLimitWithLimiter(rl)

	router := gin.New()
	router.Use(middleware)
	router.GET("/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "1.2.3.4:1234"
	router.ServeHTTP(w, req)

	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/test", nil)
	req2.RemoteAddr = "1.2.3.4:1234"
	router.ServeHTTP(w2, req2)

	w3 := httptest.NewRecorder()
	req3, _ := http.NewRequest("GET", "/test", nil)
	req3.RemoteAddr = "1.2.3.4:1234"
	router.ServeHTTP(w3, req3)

	if w3.Code != http.StatusTooManyRequests {
		t.Errorf("expected 429, got %d", w3.Code)
	}
}
