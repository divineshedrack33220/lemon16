package handlers

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"

	"coded/middleware"
	"coded/models"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

var googleOAuthConfig *oauth2.Config

func InitGoogleOAuth(cfg interface{}) {
	type googleConfig interface {
		GetGoogleClientID() string
		GetGoogleClientSecret() string
		GetGoogleRedirectURL() string
	}

	// Direct init from env (used by handler)
	clientID := getEnvOrFallback("GOOGLE_CLIENT_ID", "")
	clientSecret := getEnvOrFallback("GOOGLE_CLIENT_SECRET", "")

	if clientID != "" && clientSecret != "" {
		redirectURL := getEnvOrFallback("GOOGLE_REDIRECT_URL", "https://coded-backend.onrender.com/api/google/callback")

		googleOAuthConfig = &oauth2.Config{
			ClientID:     clientID,
			ClientSecret: clientSecret,
			RedirectURL:  redirectURL,
			Scopes: []string{
				"https://www.googleapis.com/auth/userinfo.email",
				"https://www.googleapis.com/auth/userinfo.profile",
			},
			Endpoint: google.Endpoint,
		}
		slog.Info("Google OAuth configured successfully")
	} else {
		slog.Warn("Google OAuth not configured")
	}
}

func getEnvOrFallback(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type GoogleUserInfo struct {
	ID            string `json:"id"`
	Email         string `json:"email"`
	VerifiedEmail bool   `json:"verified_email"`
	Name          string `json:"name"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
	Picture       string `json:"picture"`
	Locale        string `json:"locale"`
}

type GoogleAuthRequest struct {
	Credential string `json:"credential" binding:"required"`
}

func generateUsernameFromEmail(email string) string {
	for i := 0; i < len(email); i++ {
		if email[i] == '@' {
			username := email[:i]
			clean := strings.Builder{}
			for _, ch := range username {
				if ch != '.' {
					clean.WriteRune(ch)
				}
			}
			return clean.String() + "_" + primitive.NewObjectID().Hex()[:4]
		}
	}
	return "user_" + primitive.NewObjectID().Hex()[:8]
}

func (h *Handler) GoogleOAuthCallback(c *gin.Context) {
	code := c.Query("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Authorization code missing"})
		return
	}

	if googleOAuthConfig == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Google OAuth not configured"})
		return
	}

	ctx := c.Request.Context()
	token, err := googleOAuthConfig.Exchange(ctx, code)
	if err != nil {
		slog.Error("Google OAuth token exchange failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to exchange authorization code"})
		return
	}

	client := googleOAuthConfig.Client(ctx, token)
	resp, err := client.Get("https://www.googleapis.com/oauth2/v2/userinfo")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user information"})
		return
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read user information"})
		return
	}

	var googleUser GoogleUserInfo
	if err := json.Unmarshal(data, &googleUser); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse user information"})
		return
	}

	h.handleGoogleUser(c, googleUser, token)
}

var (
	googleKeyCache     *googleKeySet
	googleKeyCacheTime time.Time
)

type googleKeySet struct {
	Keys []googleKey `json:"keys"`
}

type googleKey struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	Use string `json:"use"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func fetchGoogleKeys() (*googleKeySet, error) {
	if googleKeyCache != nil && time.Since(googleKeyCacheTime) < time.Hour {
		return googleKeyCache, nil
	}

	resp, err := http.Get("https://www.googleapis.com/oauth2/v3/certs")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch Google keys: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Google keys endpoint returned status %d", resp.StatusCode)
	}

	var keySet googleKeySet
	if err := json.NewDecoder(resp.Body).Decode(&keySet); err != nil {
		return nil, fmt.Errorf("failed to decode Google keys: %w", err)
	}

	googleKeyCache = &keySet
	googleKeyCacheTime = time.Now()
	return &keySet, nil
}

func (h *Handler) GoogleAuthWithCredential(c *gin.Context) {
	var req GoogleAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	clientID := h.Cfg.GoogleClientID

	token, err := jwt.Parse(req.Credential, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}

		keySet, err := fetchGoogleKeys()
		if err != nil {
			return nil, fmt.Errorf("failed to fetch Google signing keys: %w", err)
		}

		kid, ok := token.Header["kid"].(string)
		if !ok {
			return nil, fmt.Errorf("missing kid header in token")
		}

		for _, key := range keySet.Keys {
			if key.Kid == kid {
				return parseRSAPublicKey(key.N, key.E)
			}
		}

		return nil, fmt.Errorf("no matching key found for kid: %s", kid)
	},
		jwt.WithIssuer("https://accounts.google.com"),
		jwt.WithIssuer("accounts.google.com"),
		jwt.WithAudience(clientID),
		jwt.WithExpirationRequired(),
	)

	if err != nil {
		slog.Error("Google credential verification failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid or expired Google credential"})
		return
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid Google credential"})
		return
	}

	googleUser := GoogleUserInfo{
		ID:      getStringClaim(claims, "sub"),
		Email:   getStringClaim(claims, "email"),
		Name:    getStringClaim(claims, "name"),
		Picture: getStringClaim(claims, "picture"),
	}

	if googleUser.Email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Email not provided by Google"})
		return
	}

	h.handleGoogleUser(c, googleUser, nil)
}

func getStringClaim(claims jwt.MapClaims, key string) string {
	if val, ok := claims[key]; ok {
		if str, ok := val.(string); ok {
			return str
		}
	}
	return ""
}

func (h *Handler) handleGoogleUser(c *gin.Context, googleUser GoogleUserInfo, token *oauth2.Token) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	user, err := h.Repos.Users.FindByEmail(ctx, googleUser.Email)

	isNewUser := false
	if err == mongo.ErrNoDocuments {
		newUser := createUserFromGoogle(googleUser)
		if err := h.Repos.Users.Create(ctx, &newUser); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user account"})
			return
		}
		user = &newUser
		isNewUser = true
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	} else {
		updateData := bson.M{
			"$set": bson.M{
				"lastSeen":     time.Now().Unix(),
				"authProvider": "google",
			},
		}

		if user.GoogleID == nil && googleUser.ID != "" {
			updateData["$set"].(bson.M)["googleId"] = googleUser.ID
		}

		if (user.Avatar == "" || user.Avatar == fallbackAvatar) && googleUser.Picture != "" {
			updateData["$set"].(bson.M)["avatar"] = googleUser.Picture
			user.Avatar = googleUser.Picture
		}

		h.Repos.Users.Update(ctx, user.ID, updateData)
	}

	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &middleware.Claims{
		UserID: user.ID.Hex(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	jwtToken := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := jwtToken.SignedString([]byte(h.Cfg.JWTSecret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate authentication token"})
		return
	}

	hasCompletedOnboarding := user.Name != "" && user.Name != user.Username && user.Gender != "" && len(user.InterestedIn) > 0

	c.JSON(http.StatusOK, gin.H{
		"token":                 tokenString,
		"userId":                user.ID.Hex(),
		"username":              user.Username,
		"avatar":                user.Avatar,
		"name":                  user.Name,
		"isNewUser":             isNewUser,
		"hasCompletedOnboarding": hasCompletedOnboarding,
		"message":               "Authentication successful",
		"expires":               expirationTime.Unix(),
	})
}

func parseRSAPublicKey(nStr, eStr string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nStr)
	if err != nil {
		return nil, fmt.Errorf("failed to decode RSA modulus: %w", err)
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eStr)
	if err != nil {
		return nil, fmt.Errorf("failed to decode RSA exponent: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{N: n, E: e}, nil
}

func createUserFromGoogle(googleUser GoogleUserInfo) models.User {
	username := generateUsernameFromEmail(googleUser.Email)

	avatar := googleUser.Picture
	if avatar == "" {
		avatar = fallbackAvatar
	}

	name := googleUser.Name
	if name == "" {
		if googleUser.GivenName != "" || googleUser.FamilyName != "" {
			name = googleUser.GivenName + " " + googleUser.FamilyName
		} else {
			name = username
		}
	}

	return models.User{
		ID:            primitive.NewObjectID(),
		Email:         googleUser.Email,
		PasswordHash:  nil,
		AuthProvider:  "google",
		GoogleID:      &googleUser.ID,
		CreatedAt:     time.Now().Unix(),
		LastSeen:      time.Now().Unix(),
		Username:      username,
		Name:          name,
		Avatar:        avatar,
		Bio:           "",
		Gender:        "",
		InterestedIn:  []string{},
		Photos:        []string{},
		Status:        "offline",
		BirthDate:     0,
		ReferralCode:  "",
		Latitude:      nil,
		Longitude:     nil,
	}
}

func (h *Handler) GetGoogleAuthURL(c *gin.Context) {
	if googleOAuthConfig == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Google OAuth not configured"})
		return
	}

	state := primitive.NewObjectID().Hex()
	url := googleOAuthConfig.AuthCodeURL(state, oauth2.AccessTypeOffline)
	c.JSON(http.StatusOK, gin.H{"url": url})
}
