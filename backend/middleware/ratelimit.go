package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type IPRateLimiter struct {
	mu       sync.Mutex
	requests map[string][]time.Time
	limit    int
	window   time.Duration
}

func NewIPRateLimiter(limit int, window time.Duration) *IPRateLimiter {
	rl := &IPRateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}
	go rl.evictLoop()
	return rl
}

func (rl *IPRateLimiter) evictLoop() {
	ticker := time.NewTicker(rl.window)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		cutoff := now.Add(-rl.window)
		for ip, reqs := range rl.requests {
			cleaned := reqs[:0]
			for _, t := range reqs {
				if t.After(cutoff) {
					cleaned = append(cleaned, t)
				}
			}
			if len(cleaned) == 0 {
				delete(rl.requests, ip)
			} else {
				rl.requests[ip] = cleaned
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *IPRateLimiter) Allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-rl.window)

	requests := rl.requests[ip]
	i := 0
	for ; i < len(requests); i++ {
		if requests[i].After(cutoff) {
			break
		}
	}
	requests = requests[i:]

	if len(requests) >= rl.limit {
		return false
	}

	rl.requests[ip] = append(requests, now)
	return true
}

func (rl *IPRateLimiter) ActiveIPs() int {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	return len(rl.requests)
}

var ipLimiter = NewIPRateLimiter(60, time.Minute)

func RateLimitMiddleware() gin.HandlerFunc {
	return RateLimitWithLimiter(ipLimiter)
}

func RateLimitWithLimiter(rl *IPRateLimiter) gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !rl.Allow(ip) {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "Too many requests"})
			c.Abort()
			return
		}
		c.Next()
	}
}
