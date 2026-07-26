package middleware

import (
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gin-gonic/gin"
)

type Metrics struct {
	RequestCount    atomic.Int64
	ErrorCount      atomic.Int64
	TotalLatencyNs  atomic.Int64
	mu              sync.RWMutex
	statusCounts    map[int]int64
	methodCounts    map[string]int64
	pathLatencies   map[string]*pathLatency
}

type pathLatency struct {
	count atomic.Int64
	total atomic.Int64
}

var AppMetrics = &Metrics{
	statusCounts: make(map[int]int64),
	methodCounts: make(map[string]int64),
	pathLatencies: make(map[string]*pathLatency),
}

func (m *Metrics) Snapshot() map[string]interface{} {
	m.mu.RLock()
	defer m.mu.RUnlock()

	statusMap := make(map[string]int64, len(m.statusCounts))
	for k, v := range m.statusCounts {
		statusMap[fmt.Sprintf("%d", k)] = v
	}

	methodMap := make(map[string]int64, len(m.methodCounts))
	for k, v := range m.methodCounts {
		methodMap[k] = v
	}

	avgLatency := int64(0)
	if reqCount := m.RequestCount.Load(); reqCount > 0 {
		avgLatency = m.TotalLatencyNs.Load() / reqCount
	}

	return map[string]interface{}{
		"total_requests": m.RequestCount.Load(),
		"error_count":    m.ErrorCount.Load(),
		"avg_latency_ms": float64(avgLatency) / float64(time.Millisecond),
		"status_codes":   statusMap,
		"methods":        methodMap,
	}
}

func (m *Metrics) record(status int, method, path string, latencyNs int64) {
	m.RequestCount.Add(1)
	m.TotalLatencyNs.Add(latencyNs)

	if status >= 400 {
		m.ErrorCount.Add(1)
	}

	m.mu.Lock()
	m.statusCounts[status]++
	m.methodCounts[method]++

	key := method + " " + path
	if _, ok := m.pathLatencies[key]; !ok {
		m.pathLatencies[key] = &pathLatency{}
	}
	m.pathLatencies[key].count.Add(1)
	m.pathLatencies[key].total.Add(latencyNs)
	m.mu.Unlock()
}

func MetricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		latency := time.Since(start).Nanoseconds()

		status := c.Writer.Status()
		method := c.Request.Method
		path := c.Request.URL.Path

		AppMetrics.record(status, method, path, latency)

		if status >= 500 {
			slog.Error("server error",
				"method", method,
				"path", path,
				"status", status,
				"latency", time.Duration(latency).String(),
			)
		}
	}
}
