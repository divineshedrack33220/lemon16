package handlers

import (
	"context"
	"net/http"
	"time"

	"coded/middleware"
	"coded/models"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"golang.org/x/crypto/bcrypt"
)

type SignupRequest struct {
	Email      string `json:"email" binding:"required,email"`
	Password   string `json:"password" binding:"required,min=6"`
	InviteCode string `json:"inviteCode"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *Handler) Signup(c *gin.Context) {
	var req SignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	existing, err := h.Repos.Users.FindByEmail(ctx, req.Email)
	if err == nil && existing != nil {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "Email already registered",
			"message": "Please use a different email or login instead",
		})
		return
	}
	if err != nil && err != mongo.ErrNoDocuments {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Database error",
			"message": "Please try again later",
		})
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Server error",
			"message": "Failed to process password",
		})
		return
	}
	hashed := string(hashedPassword)

	user := models.User{
		ID:           primitive.NewObjectID(),
		Email:        req.Email,
		PasswordHash: &hashed,
		AuthProvider: "email",
		CreatedAt:    time.Now().Unix(),
		LastSeen:     time.Now().Unix(),
		Username:     "user_" + primitive.NewObjectID().Hex()[:8],
		Name:         "",
		Avatar:       "https://upload.wikimedia.org/wikipedia/commons/8/89/Portrait_Placeholder.png",
		Bio:          "",
		Gender:       "",
		InterestedIn: []string{},
		Photos:       []string{},
		Status:       "offline",
		BirthDate:    0,
	}

	if err := h.Repos.Users.Create(ctx, &user); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Database error",
			"message": "Failed to create user account",
		})
		return
	}

	if req.InviteCode != "" {
		chat, chatErr := h.Repos.Chats.FindByInviteCode(ctx, req.InviteCode)
		if chatErr == nil && chat != nil {
			_ = h.Repos.Chats.AddParticipant(ctx, chat.ID, user.ID)
		}
	}

	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &middleware.Claims{
		UserID: user.ID.Hex(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(h.Cfg.JWTSecret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Server error",
			"message": "Failed to generate authentication token",
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message":  "User created successfully",
		"token":    tokenString,
		"userId":   user.ID.Hex(),
		"email":    user.Email,
		"username": user.Username,
	})
}

func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	user, err := h.Repos.Users.FindByEmail(ctx, req.Email)
	if err == mongo.ErrNoDocuments {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Authentication failed",
			"message": "Invalid email or password",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Database error",
			"message": "Please try again later",
		})
		return
	}

	if user.PasswordHash == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Authentication failed",
			"message": "Invalid email or password",
		})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(*user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Authentication failed",
			"message": "Invalid email or password",
		})
		return
	}

	h.Repos.Users.Update(ctx, user.ID, bson.M{"$set": bson.M{"lastSeen": time.Now().Unix()}})

	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &middleware.Claims{
		UserID: user.ID.Hex(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(h.Cfg.JWTSecret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Server error",
			"message": "Failed to generate authentication token",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":    tokenString,
		"userId":   user.ID.Hex(),
		"email":    user.Email,
		"username": user.Username,
		"avatar":   user.Avatar,
		"message":  "Login successful",
		"expires":  expirationTime.Unix(),
	})
}
