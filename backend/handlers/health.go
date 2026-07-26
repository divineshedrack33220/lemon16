package handlers

import (
	"context"
	"net/http"
	"runtime"
	"time"

	"coded/database"

	"github.com/gin-gonic/gin"
)

var startTime = time.Now()

func (h *Handler) HealthCheck(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	dbOK := true
	dbLatency := ""
	if err := database.Ping(ctx); err != nil {
		dbOK = false
		dbLatency = err.Error()
	} else {
		dbLatency = "ok"
	}

	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	status := http.StatusOK
	if !dbOK {
		status = http.StatusServiceUnavailable
	}

	c.JSON(status, gin.H{
		"status": map[string]bool{"ok": dbOK},
		"uptime": time.Since(startTime).String(),
		"db": gin.H{
			"connected": dbOK,
			"latency":   dbLatency,
		},
		"memory": gin.H{
			"alloc_mb":    float64(m.Alloc) / 1024 / 1024,
			"sys_mb":      float64(m.Sys) / 1024 / 1024,
			"gc_cycles":   m.NumGC,
		},
		"go_version":  runtime.Version(),
		"time":        time.Now().Unix(),
	})
}
