package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
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
				os.Setenv("JWT_SECRET", "dev-secret-change-in-prod")
			case "MONGODB_URI":
				log.Println("⚠️ No MongoDB URI — app will run WITHOUT database")
			}
		}
	}
}

func findFrontendPath() string {
	// Check multiple possible locations
	possiblePaths := []string{
		"./frontend",                // Same directory
		"../frontend",               // One level up (your current structure)
		"./coded/frontend",          // Nested
		os.Getenv("FRONTEND_PATH"),  // Environment variable
	}

	for _, path := range possiblePaths {
		if path == "" {
			continue
		}
		if _, err := os.Stat(path); err == nil {
			absPath, _ := filepath.Abs(path)
			log.Printf("📁 Found frontend at: %s", absPath)
			return path
		}
	}

	return "" // Not found
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

	// ---------------- STATIC FILES ----------------
	frontendPath := findFrontendPath()

	if frontendPath != "" {
		log.Println("📁 Serving frontend from:", frontendPath)

		// Serve static directories
		router.Static("/asset", frontendPath+"/asset")
		router.Static("/css", frontendPath+"/css")
		router.Static("/js", frontendPath+"/js")

		// Serve root index.html
		router.GET("/", func(c *gin.Context) {
			c.File(frontendPath + "/index.html")
		})

		// Serve manifest.json and sw.js
		router.GET("/manifest.json", func(c *gin.Context) {
			c.File(frontendPath + "/manifest.json")
		})

		router.GET("/sw.js", func(c *gin.Context) {
			c.File(frontendPath + "/sw.js")
		})

		router.GET("/offline.html", func(c *gin.Context) {
			c.File(frontendPath + "/offline.html")
		})

		// Serve specific HTML files
		htmlFiles := []string{
			"login.html", "signup.html", "chat.html", "chats.html",
			"favorites.html", "my-profile.html", "profile-settings.html",
			"view-profile.html", "post.html", "live-requests.html",
		}

		for _, file := range htmlFiles {
			// Create a new variable to capture the current file name
			f := file
			router.GET("/"+f, func(c *gin.Context) {
				c.File(frontendPath + "/" + f)
			})
		}

		// Catch-all for other HTML files
		router.GET("/:page.html", func(c *gin.Context) {
			page := c.Param("page") + ".html"
			filePath := frontendPath + "/" + page
			if _, err := os.Stat(filePath); err == nil {
				c.File(filePath)
			} else {
				c.String(404, "Page not found")
			}
		})

	} else {
		log.Println("⚠️ No frontend found — API mode only")
		log.Println("   Looking in: ./frontend, ../frontend")
	}

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
		if frontendPath != "" {
			log.Printf("📍 Frontend URL: http://localhost:%s", port)
		}
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