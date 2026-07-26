package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"coded/config"
	"coded/internal/testutil"
	"coded/middleware"
	"coded/models"
	"coded/repository"
	"coded/websocket"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"golang.org/x/crypto/bcrypt"
)

func setupTestHandler(t *testing.T, repos *repository.Repositories) (*Handler, *gin.Engine) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	t.Setenv("JWT_SECRET", "test-secret")
	t.Setenv("GIN_MODE", "test")
	cfg := &config.Config{
		JWTSecret: "test-secret",
		GinMode:   "test",
	}
	wsManager := websocket.NewManager()
	h := NewHandler(repos, wsManager, cfg)
	router := gin.New()
	return h, router
}

func jsonBody(v interface{}) *bytes.Buffer {
	data, _ := json.Marshal(v)
	return bytes.NewBuffer(data)
}

func testToken(userID string) string {
	claims := &middleware.Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, _ := token.SignedString([]byte("test-secret"))
	return tokenString
}

func TestSignup_Success(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByEmailFn: func(ctx context.Context, email string) (*models.User, error) {
				return nil, mongo.ErrNoDocuments
			},
			CreateFn: func(ctx context.Context, user *models.User) error {
				return nil
			},
		},
		Chats: &testutil.MockChatRepo{},
	})

	router.POST("/api/signup", h.Signup)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/signup", jsonBody(map[string]string{
		"email":    "test@example.com",
		"password": "password123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["token"] == nil || resp["token"] == "" {
		t.Error("expected token in response")
	}
	if resp["userId"] == nil || resp["userId"] == "" {
		t.Error("expected userId in response")
	}
}

func TestSignup_DuplicateEmail(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByEmailFn: func(ctx context.Context, email string) (*models.User, error) {
				return &models.User{
					ID:    primitive.NewObjectID(),
					Email: email,
				}, nil
			},
		},
	})

	router.POST("/api/signup", h.Signup)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/signup", jsonBody(map[string]string{
		"email":    "existing@example.com",
		"password": "password123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Errorf("expected 409, got %d: %s", w.Code, w.Body.String())
	}
}

func TestSignup_InvalidEmail(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{},
	})

	router.POST("/api/signup", h.Signup)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/signup", jsonBody(map[string]string{
		"email":    "not-an-email",
		"password": "password123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestSignup_ShortPassword(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{},
	})

	router.POST("/api/signup", h.Signup)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/signup", jsonBody(map[string]string{
		"email":    "test@example.com",
		"password": "123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestLogin_Success(t *testing.T) {
	hashed, _ := bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)
	hashedStr := string(hashed)

	userID := primitive.NewObjectID()
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByEmailFn: func(ctx context.Context, email string) (*models.User, error) {
				return &models.User{
					ID:           userID,
					Email:        email,
					PasswordHash: &hashedStr,
					Username:     "testuser",
					Avatar:       "avatar.png",
				}, nil
			},
			UpdateFn: func(ctx context.Context, id primitive.ObjectID, update bson.M) (*mongo.UpdateResult, error) {
				return &mongo.UpdateResult{ModifiedCount: 1}, nil
			},
		},
	})

	router.POST("/api/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/login", jsonBody(map[string]string{
		"email":    "test@example.com",
		"password": "password123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["token"] == nil || resp["token"] == "" {
		t.Error("expected token in response")
	}
}

func TestLogin_WrongPassword(t *testing.T) {
	hashed, _ := bcrypt.GenerateFromPassword([]byte("correctpassword"), bcrypt.DefaultCost)
	hashedStr := string(hashed)

	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByEmailFn: func(ctx context.Context, email string) (*models.User, error) {
				return &models.User{
					ID:           primitive.NewObjectID(),
					Email:        email,
					PasswordHash: &hashedStr,
				}, nil
			},
		},
	})

	router.POST("/api/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/login", jsonBody(map[string]string{
		"email":    "test@example.com",
		"password": "wrongpassword",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d: %s", w.Code, w.Body.String())
	}
}

func TestLogin_UserNotFound(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByEmailFn: func(ctx context.Context, email string) (*models.User, error) {
				return nil, mongo.ErrNoDocuments
			},
		},
	})

	router.POST("/api/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/login", jsonBody(map[string]string{
		"email":    "nobody@example.com",
		"password": "password123",
	}))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d: %s", w.Code, w.Body.String())
	}
}

func TestGetMyProfile_Success(t *testing.T) {
	userID := primitive.NewObjectID()
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{
			FindByIDFn: func(ctx context.Context, id primitive.ObjectID) (*models.User, error) {
				return &models.User{
					ID:       id,
					Name:     "Test User",
					Email:    "test@example.com",
					Username: "testuser",
					Avatar:   "avatar.png",
					Bio:      "Hello world",
					Gender:   "male",
					Status:   "online",
				}, nil
			},
		},
	})

	protected := router.Group("/api")
	protected.Use(middleware.JWTAuthMiddleware())
	protected.GET("/me", h.GetMyProfile)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/me", nil)
	req.Header.Set("Authorization", "Bearer "+testToken(userID.Hex()))
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["name"] != "Test User" {
		t.Errorf("expected name='Test User', got %v", resp["name"])
	}
}

func TestGetMyProfile_Unauthenticated(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{},
	})

	protected := router.Group("/api")
	protected.Use(middleware.JWTAuthMiddleware())
	protected.GET("/me", h.GetMyProfile)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/me", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestHealthCheck(t *testing.T) {
	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{},
	})

	router.GET("/health", h.HealthCheck)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/health", nil)
	router.ServeHTTP(w, req)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)

	if resp["uptime"] == nil {
		t.Error("expected uptime in health response")
	}
	if resp["memory"] == nil {
		t.Error("expected memory stats in health response")
	}
}

func TestFavorite_AddAndRemove(t *testing.T) {
	userID := primitive.NewObjectID()
	targetID := primitive.NewObjectID()
	favExists := false

	h, router := setupTestHandler(t, &repository.Repositories{
		Users: &testutil.MockUserRepo{},
		Favorites: &testutil.MockFavoriteRepo{
			CreateFn: func(ctx context.Context, fav *models.Favorite) error {
				favExists = true
				return nil
			},
			ExistsFn: func(ctx context.Context, uid, tid primitive.ObjectID) (bool, error) {
				return favExists, nil
			},
			DeleteFn: func(ctx context.Context, uid, tid primitive.ObjectID) (*mongo.DeleteResult, error) {
				favExists = false
				return &mongo.DeleteResult{DeletedCount: 1}, nil
			},
			FindByUserFn: func(ctx context.Context, uid primitive.ObjectID, limit int64) ([]models.Favorite, error) {
				return nil, nil
			},
		},
	})

	protected := router.Group("/api")
	protected.Use(middleware.JWTAuthMiddleware())
	protected.POST("/favorite", h.AddFavorite)
	protected.DELETE("/favorite", h.RemoveFavorite)
	protected.GET("/favorites", h.GetFavorites)

	// Add favorite
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/favorite", jsonBody(map[string]string{
		"targetUserId": targetID.Hex(),
	}))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+testToken(userID.Hex()))
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("add favorite: expected 201, got %d: %s", w.Code, w.Body.String())
	}

	// Remove favorite
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("DELETE", "/api/favorite", jsonBody(map[string]string{
		"targetUserId": targetID.Hex(),
	}))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("Authorization", "Bearer "+testToken(userID.Hex()))
	router.ServeHTTP(w2, req2)

	if w2.Code != http.StatusOK {
		t.Errorf("remove favorite: expected 200, got %d: %s", w2.Code, w2.Body.String())
	}
}
