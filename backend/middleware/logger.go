package middleware

import (
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
)

func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		method := c.Request.Method
		ip := c.ClientIP()
		userID, _ := c.Get("userId")
		errors := c.Errors.ByType(gin.ErrorTypePrivate).String()

		attrs := []slog.Attr{
			slog.Int("status", status),
			slog.String("method", method),
			slog.String("path", path),
			slog.String("query", query),
			slog.String("ip", ip),
			slog.String("latency", latency.String()),
			slog.Int("bytes", c.Writer.Size()),
		}

		if userID != nil {
			attrs = append(attrs, slog.String("user_id", userID.(string)))
		}

		if requestID, exists := c.Get("request_id"); exists {
			attrs = append(attrs, slog.String("request_id", requestID.(string)))
		}

		if errors != "" {
			attrs = append(attrs, slog.String("errors", errors))
		}

		level := slog.LevelInfo
		if status >= 500 {
			level = slog.LevelError
		} else if status >= 400 {
			level = slog.LevelWarn
		}

		slog.LogAttrs(c.Request.Context(), level, "request",
			attrs...,
		)
	}
}
