package routes

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"coded/handlers"
	"coded/middleware"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

const webDirEnv = "WEB_DIR"

func SetupRouter(h *handlers.Handler, allowedOrigins []string) *gin.Engine {
	router := gin.New()
	router.Use(gin.Recovery())

	router.Use(middleware.RequestID())
	router.Use(middleware.RequestLogger())
	router.Use(middleware.MetricsMiddleware())

	// Health check with live DB ping
	router.GET("/health", h.HealthCheck)
	router.GET("/api/health", h.HealthCheck)

	// Metrics endpoint (internal only)
	router.GET("/metrics", func(c *gin.Context) {
		m := middleware.AppMetrics
		snapshot := m.Snapshot()
		c.JSON(http.StatusOK, snapshot)
	})

	// CORS
	router.Use(cors.New(cors.Config{
		AllowOriginFunc: func(origin string) bool {
			if origin == "" {
				return true
			}
			for _, allowed := range allowedOrigins {
				if allowed == "*" {
					return true
				}
				if origin == allowed {
					return true
				}
				if strings.HasSuffix(allowed, ":*") {
					prefix := allowed[:len(allowed)-1]
					if strings.HasPrefix(origin, prefix) {
						return true
					}
				}
				if strings.Contains(allowed, "*.") {
					pattern := strings.Replace(allowed, "*.", "", 1)
					if strings.HasSuffix(origin, pattern) {
						return true
					}
				}
			}
			return false
		},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "Accept", "X-Requested-With", "X-Request-ID"},
		ExposeHeaders:    []string{"Content-Length", "Content-Type", "X-Request-ID"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Static web files (must be before catch-all NoRoute)
	webDir := os.Getenv(webDirEnv)
	if webDir == "" {
		webDir = "./web"
	}
	if _, err := os.Stat(webDir); err == nil {
		router.Static("/assets", filepath.Clean(webDir)+"/assets")
		router.Static("/canvaskit", filepath.Clean(webDir)+"/canvaskit")
		router.Static("/icons", filepath.Clean(webDir)+"/icons")
		router.Static("/flutter.js", filepath.Clean(webDir)+"/flutter.js")
		router.Static("/flutter_bootstrap.js", filepath.Clean(webDir)+"/flutter_bootstrap.js")
		router.Static("/flutter_service_worker.js", filepath.Clean(webDir)+"/flutter_service_worker.js")
		router.Static("/main.dart.js", filepath.Clean(webDir)+"/main.dart.js")
		router.Static("/manifest.json", filepath.Clean(webDir)+"/manifest.json")
		router.Static("/version.json", filepath.Clean(webDir)+"/version.json")
	}

	// SPA fallback - serve index.html for any unmatched web route
	router.NoRoute(func(c *gin.Context) {
		if len(c.Request.URL.Path) >= 4 && c.Request.URL.Path[:4] == "/api" {
			c.JSON(404, gin.H{
				"error":   "Endpoint not found",
				"path":    c.Request.URL.Path,
				"message": "Check the API documentation for available endpoints",
			})
			return
		}
		if c.Request.URL.Path == "/ws" {
			c.JSON(404, gin.H{
				"error": "WebSocket endpoint not found",
				"path":  c.Request.URL.Path,
			})
			return
		}
		// Serve SPA index.html for client-side routing
		if webDir != "" {
			indexPath := filepath.Join(webDir, "index.html")
			if _, err := os.Stat(indexPath); err == nil {
				c.Header("Cache-Control", "no-cache")
				c.File(indexPath)
				return
			}
		}
		c.JSON(404, gin.H{
			"error":   "Not found",
			"message": "Resource not found",
		})
	})

	authLimiter := middleware.NewIPRateLimiter(10, time.Minute)
	searchLimiter := middleware.NewIPRateLimiter(30, time.Minute)

	// Public routes
	router.POST("/api/signup", middleware.RateLimitWithLimiter(authLimiter), h.Signup)
	router.POST("/api/login", middleware.RateLimitWithLimiter(authLimiter), h.Login)
	router.GET("/api/vapid-public-key", h.GetVapidPublicKey)
	router.GET("/api/groups/invite/:code", h.GetGroupInfoByInviteCode)

	router.GET("/api/google/auth-url", h.GetGoogleAuthURL)
	router.GET("/api/google/callback", h.GoogleOAuthCallback)
	router.POST("/api/google-auth", middleware.RateLimitWithLimiter(authLimiter), h.GoogleAuthWithCredential)

	// Protected routes
	protected := router.Group("/api")
	protected.Use(middleware.JWTAuthMiddleware())

	protected.GET("/me", h.GetMyProfile)
	protected.PUT("/me", h.UpdateMyProfile)
	protected.DELETE("/me", h.DeleteMyProfile)
	protected.GET("/user/:id", h.GetUser)
	protected.PUT("/me/status", h.UpdateUserStatus)
	protected.POST("/block", h.BlockUser)

	protected.GET("/test-auth", h.TestAuth)

	protected.GET("/users/nearby", h.GetNearbyUsers)
	protected.GET("/users/search", middleware.RateLimitWithLimiter(searchLimiter), h.SearchUsers)

	protected.POST("/post", h.CreatePost)
	protected.GET("/feed", h.GetFeed)
	protected.GET("/user/:id/posts", h.GetUserPosts)
	protected.GET("/my/posts", h.GetMyPosts)

	protected.POST("/favorite", h.AddFavorite)
	protected.DELETE("/favorite", h.RemoveFavorite)
	protected.GET("/favorites", h.GetFavorites)

	protected.GET("/matches", h.GetMatches)

	protected.GET("/chats", h.GetChatList)
	protected.POST("/chats", h.CreateChat)
	protected.GET("/chats/:id", h.GetChat)
	protected.PUT("/chats/:id", h.UpdateGroupChat)
	protected.POST("/chats/:id/admin", h.PromoteToAdmin)
	protected.DELETE("/chats/:id/participants/:userId", h.RemoveGroupMember)
	protected.POST("/chats/:id/invite", h.GenerateGroupInviteCode)
	protected.POST("/groups/join", h.JoinGroupByInviteCode)
	protected.POST("/chats/:id/participants", h.AddGroupMember)

	protected.POST("/message", h.SendMessage)
	protected.GET("/messages/:id", h.GetMessages)
	protected.POST("/messages/:id/read", h.MarkAsRead)
	protected.POST("/typing", h.SendTypingIndicator)
	protected.POST("/messages/:id/react", h.ReactToMessage)

	protected.POST("/upload-photo", h.UploadPhoto)

	protected.GET("/me/referral", h.GetReferral)

	protected.POST("/subscribe", h.SubscribePush)

	return router
}
