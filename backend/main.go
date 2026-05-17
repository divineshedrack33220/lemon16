package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"coded/database"
	"coded/handlers"
	"coded/routes"
	"coded/websocket"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func validateEnv() {
	required := []string{
		"JWT_SECRET",
		"MONGODB_URI",
	}

	for _, env := range required {
		if os.Getenv(env) == "" {
			log.Printf("⚠️ Missing env: %s", env)

			switch env {
			case "JWT_SECRET":
				if os.Getenv("GIN_MODE") == "release" {
					log.Fatal("❌ FATAL: JWT_SECRET must be set in release mode!")
				}
				os.Setenv("JWT_SECRET", "dev-secret-change-in-prod")
				log.Println("⚠️ Using insecure default JWT_SECRET (Development only)")
			case "MONGODB_URI":
				log.Println("⚠️ No MongoDB URI — app will run WITHOUT database (degraded mode)")
			}
		}
	}
}


func main() {
	log.Println("🚀 Starting backend...")

	_ = godotenv.Load()
	validateEnv()

	// Initialize VAPID keys for push notifications
	handlers.InitVAPIDKeys()

	// ---------------- DB CONNECTION (NON-BLOCKING) ----------------
	log.Println("🔌 Connecting to MongoDB...")
	var dbConnected bool

	for i := 1; i <= 3; i++ {
		if err := database.ConnectDB(); err != nil {
			log.Printf("❌ DB attempt %d failed: %v", i, err)
			time.Sleep(2 * time.Second)
		} else {
			dbConnected = true
			break
		}
	}

	if dbConnected {
		log.Println("✅ MongoDB connected")

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if err := database.Client.Ping(ctx, nil); err != nil {
			log.Println("⚠️ MongoDB ping failed:", err)
		}
	} else {
		log.Println("⚠️ Running WITHOUT MongoDB (degraded mode)")
	}

	// ---------------- WEBSOCKET ----------------
	wsManager := websocket.NewManager()
	go wsManager.Start()
	handlers.SetWebSocketManager(wsManager)

	// ---------------- GIN MODE ----------------
	if os.Getenv("GIN_MODE") == "release" {
		gin.SetMode(gin.ReleaseMode)
	} else {
		gin.SetMode(gin.DebugMode)
	}

	// ---------------- ROUTER ----------------
	router := routes.SetupRouter()

	// Log DB status for monitoring
	log.Printf("📊 Database connection status: %v", dbConnected)

	// WebSocket endpoint
	router.GET("/ws", func(c *gin.Context) {
		websocket.WebSocketHandler(wsManager)(c.Writer, c.Request)
	})


	// ---------------- PORT ----------------
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:         "0.0.0.0:" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// ---------------- START SERVER ----------------
	go func() {
		log.Printf("🌐 Running on port %s", port)
		log.Printf("📍 API Base URL: http://localhost:%s/api", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("Server crash:", err)
		}
	}()

	log.Println("✅ Server started successfully")

	// ---------------- GRACEFUL SHUTDOWN ----------------
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	<-quit
	log.Println("🛑 Shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Println("❌ Forced shutdown:", err)
	}

	if database.Client != nil {
		_ = database.Client.Disconnect(ctx)
	}

	log.Println("👋 Server stopped")
}