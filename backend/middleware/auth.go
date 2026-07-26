package middleware

import (
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID string `json:"userId"`
	jwt.RegisteredClaims
}

// GetJWTSecret returns the JWT secret, failing hard if not set in release mode.
func GetJWTSecret() string {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		if os.Getenv("GIN_MODE") == "release" {
			panic("JWT_SECRET environment variable is required in production")
		}
		secret = "dev-secret-change-in-prod"
	}
	return secret
}

func JWTAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip middleware for OPTIONS requests (CORS preflight)
		if c.Request.Method == "OPTIONS" {
			c.Next()
			return
		}

		// Try to get token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			// Try to get from query parameter
			token := c.Query("token")
			if token == "" {
				c.JSON(http.StatusUnauthorized, gin.H{
					"error":   "Authentication required",
					"message": "No authorization token provided",
				})
				c.Abort()
				return
			}
			authHeader = "Bearer " + token
		}

		// Check if it's a Bearer token
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":   "Invalid authorization header",
				"message": "Format should be: Bearer <token>",
			})
			c.Abort()
			return
		}

		tokenString := parts[1]

		// Parse and validate the token
		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			// Validate the alg is what we expect
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(GetJWTSecret()), nil
		})

		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":   "Invalid token",
				"message": "Token validation failed",
			})
			c.Abort()
			return
		}

		if !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":   "Invalid token",
				"message": "Token is not valid",
			})
			c.Abort()
			return
		}

		// Token is valid, set userId in context
		c.Set("userId", claims.UserID)
		
		// Continue to the next handler
		c.Next()
	}
}