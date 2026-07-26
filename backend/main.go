package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"coded/config"
	"coded/database"
	"coded/handlers"
	"coded/repository"
	"coded/routes"
	"coded/websocket"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	slog.Info("starting backend")

	_ = godotenv.Load()
	cfg := config.Load()

	gin.SetMode(cfg.GinMode)

	if cfg.IsRender || os.Getenv("GOMAXPROCS") == "1" {
		runtime.GOMAXPROCS(1)
	}

	handlers.InitVAPIDKeys()
	handlers.InitGoogleOAuth(nil)

	slog.Info("connecting to MongoDB")
	var dbConnected bool

	if err := database.ConnectDB(cfg); err != nil {
		slog.Error("running without MongoDB", "error", err)
		dbConnected = false
	} else {
		dbConnected = true
	}

	repos := repository.New(database.DB)

	wsManager := websocket.NewManager()
	go wsManager.Start()

	h := handlers.NewHandler(repos, wsManager, cfg)

	router := routes.SetupRouter(h, cfg.AllowedOrigins)

	slog.Info("database connection status", "connected", dbConnected)

	router.GET("/ws", func(c *gin.Context) {
		websocket.WebSocketHandler(wsManager)(c.Writer, c.Request)
	})

	server := &http.Server{
		Addr:         "0.0.0.0:" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("server listening", "addr", "0.0.0.0:"+cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server crashed", "error", err)
			os.Exit(1)
		}
	}()

	slog.Info("server started successfully")

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	wsManager.Shutdown()

	if err := server.Shutdown(ctx); err != nil {
		slog.Error("forced shutdown", "error", err)
	}

	if database.Client != nil {
		_ = database.Client.Disconnect(ctx)
	}

	slog.Info("server stopped")
}
