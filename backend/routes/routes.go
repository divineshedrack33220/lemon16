package routes

import (
    "os"
    "strings"
    "time"

    "coded/handlers"
    "coded/middleware"

    "github.com/gin-contrib/cors"
    "github.com/gin-gonic/gin"
)

func SetupRouter() *gin.Engine {
    router := gin.Default()

    // Add health check endpoint for testing
    router.GET("/api/health", func(c *gin.Context) {
        c.JSON(200, gin.H{
            "status":  "ok",
            "message": "Coded API is running",
            "time":    time.Now().Unix(),
            "ws":      "WebSocket available at /ws",
            "google":  "Google OAuth available",
        })
    })

    // CORS configuration - Updated for Render
    allowOrigins := []string{
        "http://localhost:*",
        "http://127.0.0.1:*",
        "http://localhost:5500",
        "http://localhost:3000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:5500",
        "http://localhost:10000",
        "http://127.0.0.1:10000",
        "http://localhost:*",
        "https://coded-backend.onrender.com",
        "https://*.onrender.com",
    }
    
    // Add allowed origins from environment variable
    if envOrigins := os.Getenv("ALLOWED_ORIGINS"); envOrigins != "" {
        allowOrigins = append(allowOrigins, strings.Split(envOrigins, ",")...)
    }

    router.Use(cors.New(cors.Config{
        AllowOriginFunc: func(origin string) bool {
		return true // Allow all for development
	},
        AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
        AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "Accept", "X-Requested-With"},
        ExposeHeaders:    []string{"Content-Length", "Content-Type"},
        AllowCredentials: true,
        MaxAge:           12 * time.Hour,
    }))

    // Public routes (no auth required)
    router.POST("/api/signup", handlers.Signup)
    router.POST("/api/login", handlers.Login)
    router.GET("/api/vapid-public-key", handlers.GetVapidPublicKey)
    router.GET("/api/groups/invite/:code", handlers.GetGroupInfoByInviteCode)
    
    // Google OAuth routes
    router.GET("/api/google/auth-url", handlers.GetGoogleAuthURL)
    router.GET("/api/google/callback", handlers.GoogleOAuthCallback)
    router.POST("/api/google-auth", handlers.GoogleAuthWithCredential)

    // Protected routes group
    protected := router.Group("/api")
    protected.Use(middleware.JWTAuthMiddleware())

    // Profile
    protected.GET("/me", handlers.GetMyProfile)
    protected.PUT("/me", handlers.UpdateMyProfile)
    protected.DELETE("/me", handlers.DeleteMyProfile)
    protected.GET("/user/:id", handlers.GetUser)
    protected.PUT("/me/status", handlers.UpdateUserStatus)
    protected.POST("/block", handlers.BlockUser)

    // Test endpoint
    protected.GET("/test-auth", handlers.TestAuth)

    // Users
    protected.GET("/users/nearby", handlers.GetNearbyUsers)
    protected.GET("/users/search", handlers.SearchUsers)

    // Posts
    protected.POST("/post", handlers.CreatePost)
    protected.GET("/feed", handlers.GetFeed)
    protected.GET("/user/:id/posts", handlers.GetUserPosts)
    protected.GET("/my/posts", handlers.GetMyPosts)

    // Favorites
    protected.POST("/favorite", handlers.AddFavorite)
    protected.DELETE("/favorite", handlers.RemoveFavorite)
    protected.GET("/favorites", handlers.GetFavorites)

    // Matches
    protected.GET("/matches", handlers.GetMatches)

    // Chats
    protected.GET("/chats", handlers.GetChatList)
    protected.POST("/chats", handlers.CreateChat)
    protected.GET("/chats/:id", handlers.GetChat)
    protected.PUT("/chats/:id", handlers.UpdateGroupChat)
    protected.POST("/chats/:id/admin", handlers.PromoteToAdmin)
    protected.DELETE("/chats/:id/participants/:userId", handlers.RemoveGroupMember)
    protected.POST("/chats/:id/invite", handlers.GenerateGroupInviteCode)
    protected.POST("/groups/join", handlers.JoinGroupByInviteCode)
    protected.POST("/chats/:id/participants", handlers.AddGroupMember)

    // Messages
    protected.POST("/message", handlers.SendMessage)
    protected.GET("/messages/:id", handlers.GetMessages)
    protected.POST("/messages/:id/read", handlers.MarkAsRead)
    protected.POST("/typing", handlers.SendTypingIndicator)
    protected.POST("/messages/:id/react", handlers.ReactToMessage)

    // Photo upload
    protected.POST("/upload-photo", handlers.UploadPhoto)

    // Referral
    protected.GET("/me/referral", handlers.GetReferral)

    // Push subscriptions
    protected.POST("/subscribe", handlers.SubscribePush)

    // Add a catch-all for undefined API routes
    router.NoRoute(func(c *gin.Context) {
        // If it's an API route, return JSON 404
        if len(c.Request.URL.Path) >= 4 && c.Request.URL.Path[:4] == "/api" {
            c.JSON(404, gin.H{
                "error":   "Endpoint not found",
                "path":    c.Request.URL.Path,
                "message": "Check the API documentation for available endpoints",
            })
            return
        }
        // For WebSocket routes
        if c.Request.URL.Path == "/ws" {
            c.JSON(404, gin.H{
                "error":   "WebSocket endpoint not found",
                "path":    c.Request.URL.Path,
            })
            return
        }
        // For non-API routes, let Gin handle it
        c.Next()
    })

    return router
}