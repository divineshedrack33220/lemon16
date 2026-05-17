package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log"
	"net/http"
	"os"
	"time"

	"coded/database"
	"coded/models"

	"github.com/cloudinary/cloudinary-go/v2"
	"github.com/cloudinary/cloudinary-go/v2/api/uploader"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// DO NOT DECLARE fallbackAvatar HERE - it's now in common.go
// const fallbackAvatar = "https://upload.wikimedia.org/wikipedia/commons/8/89/Portrait_Placeholder.png" // REMOVE THIS LINE

type OnboardingData struct {
	Name         string   `json:"name" form:"name"`
	Username     string   `json:"username" form:"username"`
	BirthDate    int64    `json:"birthDate,omitempty" form:"birthDate"`
	Gender       string   `json:"gender" form:"gender"`
	InterestedIn []string `json:"interestedIn" form:"interestedIn"`
	Bio          string   `json:"bio" form:"bio"`
	Status       string   `json:"status" form:"status"`
	Photos       []string `json:"photos" form:"photos"`
	Latitude     *float64 `json:"latitude,omitempty" form:"latitude"`
	Longitude    *float64 `json:"longitude,omitempty" form:"longitude"`
}

// Helper: generate a unique 8-character referral code
func generateReferralCode() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// GetUser - Fixed to always return 200 OK with fallback data for missing users
func GetUser(c *gin.Context) {
	userIDStr := c.Param("id")
	log.Printf("[GetUser] Request for user ID: %s", userIDStr)
	
	var userID primitive.ObjectID
	var err error
	
	// Try to parse as ObjectID, if invalid, return fallback
	userID, err = primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		log.Printf("[GetUser] Invalid user ID format: %s, returning fallback", userIDStr)
		c.JSON(http.StatusOK, gin.H{
			"id":         userIDStr,
			"name":       "Unknown User",
			"avatar":     fallbackAvatar, // Using the shared constant
			"status":     "offline",
			"bio":        "",
			"photos":     []string{},
			"age":        0,
			"distance":   0,
			"rating":     0,
			"lastActive": 0,
			"interests":  []string{},
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	var user models.User
	err = usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&user)
	if err == mongo.ErrNoDocuments {
		log.Printf("[GetUser] User not found: %s, returning fallback", userIDStr)
		c.JSON(http.StatusOK, gin.H{
			"id":         userID.Hex(),
			"name":       "Unknown User",
			"avatar":     fallbackAvatar, // Using the shared constant
			"status":     "offline",
			"bio":        "",
			"photos":     []string{},
			"age":        0,
			"distance":   0,
			"rating":     0,
			"lastActive": 0,
			"interests":  []string{},
		})
		return
	}
	if err != nil {
		log.Printf("[GetUser] Database error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch user"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// GetMyProfile - Fixed with better error handling
func GetMyProfile(c *gin.Context) {
	// Get userId from context (set by middleware)
	userIDStr := c.GetString("userId")
	
	// Debug logging
	log.Printf("[GetMyProfile] Request received for userID: %s", userIDStr)
	
	if userIDStr == "" {
		log.Println("[GetMyProfile] ERROR: No userId in context")
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Not authenticated",
			"code":    "UNAUTHORIZED",
			"message": "Please log in first",
		})
		return
	}

	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		log.Printf("[GetMyProfile] ERROR: Invalid user ID format: %s, error: %v", userIDStr, err)
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid user ID",
			"code":    "INVALID_ID",
			"message": "User ID is not valid",
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")
	log.Printf("[GetMyProfile] Querying MongoDB for user: %s", userID.Hex())

	var user models.User
	err = usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&user)
	if err == mongo.ErrNoDocuments {
		log.Printf("[GetMyProfile] ERROR: User not found: %s", userID.Hex())
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "Profile not found",
			"code":    "NOT_FOUND",
			"message": "User profile does not exist",
		})
		return
	}
	if err != nil {
		log.Printf("[GetMyProfile] ERROR: Database error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Database error",
			"code":    "DB_ERROR",
			"message": "Failed to fetch profile from database",
		})
		return
	}

	// Log successful fetch
	log.Printf("[GetMyProfile] SUCCESS: Found user: %s (%s)", user.Name, user.Email)

	// Ensure user has basic fields
	// NOTE: Do NOT override empty avatar here — let the frontend handle fallbacks
	// so users can have no avatar and rely on gallery photos or monogram.
	if user.Status == "" {
		user.Status = "offline"
	}
	if user.Photos == nil {
		user.Photos = []string{}
	}
	if user.InterestedIn == nil {
		user.InterestedIn = []string{}
	}

	// Generate referral code if missing
	if user.ReferralCode == "" {
		var code string
		for {
			code, err = generateReferralCode()
			if err != nil {
				log.Printf("[GetMyProfile] Failed to generate referral code: %v", err)
				break
			}
			count, _ := usersColl.CountDocuments(ctx, bson.M{"referralCode": code})
			if count == 0 {
				break
			}
		}

		if code != "" {
			_, err = usersColl.UpdateOne(ctx, bson.M{"_id": userID}, bson.M{"$set": bson.M{"referralCode": code}})
			if err != nil {
				log.Printf("[GetMyProfile] Failed to save referral code: %v", err)
			} else {
				user.ReferralCode = code
			}
		}
	}

	// Return successful response
	c.JSON(http.StatusOK, gin.H{
		"id":           user.ID.Hex(),
		"email":        user.Email,
		"name":         user.Name,
		"username":     user.Username,
		"avatar":       user.Avatar,
		"status":       user.Status,
		"bio":          user.Bio,
		"photos":       user.Photos,
		"birthDate":    user.BirthDate,
		"gender":       user.Gender,
		"interestedIn": user.InterestedIn,
		"latitude":     user.Latitude,
		"longitude":    user.Longitude,
		"createdAt":    user.CreatedAt,
		"lastSeen":     user.LastSeen,
		"referralCode": user.ReferralCode,
		"message":      "Profile fetched successfully",
	})
}

func UpdateMyProfile(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	update := bson.M{"$set": bson.M{}}

	contentType := c.ContentType()

	// Use a flexible raw map to capture all fields including avatar URL from JSON
	var rawData map[string]interface{}
	var data OnboardingData

	if contentType == "application/json" {
		if err := c.ShouldBindJSON(&rawData); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON data"})
			return
		}
		// Map raw fields to OnboardingData
		if v, ok := rawData["name"].(string); ok {
			data.Name = v
		}
		if v, ok := rawData["username"].(string); ok {
			data.Username = v
		}
		if v, ok := rawData["bio"].(string); ok {
			data.Bio = v
		}
		if v, ok := rawData["gender"].(string); ok {
			data.Gender = v
		}
		if v, ok := rawData["status"].(string); ok {
			data.Status = v
		}
		if v, ok := rawData["interestedIn"].([]interface{}); ok {
			for _, item := range v {
				if s, ok := item.(string); ok {
					data.InterestedIn = append(data.InterestedIn, s)
				}
			}
		}
		if v, ok := rawData["photos"].([]interface{}); ok {
			for _, item := range v {
				if s, ok := item.(string); ok {
					data.Photos = append(data.Photos, s)
				}
			}
		}
		// Handle avatar URL directly from JSON body
		if v, ok := rawData["avatar"].(string); ok && v != "" {
			update["$set"].(bson.M)["avatar"] = v
		}
	} else {
		if err := c.Request.ParseMultipartForm(10 << 20); err != nil && err != http.ErrNotMultipart {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form data"})
			return
		}
		if err := c.ShouldBind(&data); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid form data"})
			return
		}
	}

	if data.Name != "" {
		update["$set"].(bson.M)["name"] = data.Name
	}
	if data.Username != "" {
		update["$set"].(bson.M)["username"] = data.Username
	}
	if data.BirthDate != 0 {
		update["$set"].(bson.M)["birthDate"] = data.BirthDate
	}
	if data.Gender != "" {
		update["$set"].(bson.M)["gender"] = data.Gender
	}
	if len(data.InterestedIn) > 0 {
		update["$set"].(bson.M)["interestedIn"] = data.InterestedIn
	}
	if data.Bio != "" {
		update["$set"].(bson.M)["bio"] = data.Bio
	}
	if data.Status != "" {
		update["$set"].(bson.M)["status"] = data.Status
	}
	if len(data.Photos) > 0 {
		update["$set"].(bson.M)["photos"] = data.Photos
	}
	if data.Latitude != nil {
		update["$set"].(bson.M)["latitude"] = *data.Latitude
	}
	if data.Longitude != nil {
		update["$set"].(bson.M)["longitude"] = *data.Longitude
	}

	// Handle avatar file upload (multipart only)
	if contentType != "application/json" {
		avatarFile, _, err := c.Request.FormFile("avatar")
		if err == nil {
			defer avatarFile.Close()

			cld, err := cloudinary.NewFromURL(os.Getenv("CLOUDINARY_URL"))
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Cloudinary configuration error"})
				return
			}

			uploadParams := uploader.UploadParams{
				Folder:         "coded/avatars",
				PublicID:       userID.Hex(),
				Transformation: "c_limit,w_400,h_400,q_auto",
			}

			uploadResult, err := cld.Upload.Upload(ctx, avatarFile, uploadParams)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to upload avatar to Cloudinary"})
				return
			}

			update["$set"].(bson.M)["avatar"] = uploadResult.SecureURL
		}
	}

	if len(update["$set"].(bson.M)) == 0 {
		c.JSON(http.StatusOK, gin.H{"message": "No changes to update"})
		return
	}

	result, err := usersColl.UpdateOne(ctx, bson.M{"_id": userID}, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile"})
		return
	}
	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Fetch and return the updated profile so the frontend can refresh without a second request
	var updatedUser models.User
	if fetchErr := usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&updatedUser); fetchErr != nil {
		// Fallback to simple success if re-fetch fails
		c.JSON(http.StatusOK, gin.H{"message": "Profile updated successfully"})
		return
	}
	if updatedUser.Photos == nil {
		updatedUser.Photos = []string{}
	}
	if updatedUser.InterestedIn == nil {
		updatedUser.InterestedIn = []string{}
	}
	c.JSON(http.StatusOK, gin.H{
		"message":      "Profile updated successfully",
		"id":           updatedUser.ID.Hex(),
		"email":        updatedUser.Email,
		"name":         updatedUser.Name,
		"username":     updatedUser.Username,
		"avatar":       updatedUser.Avatar,
		"status":       updatedUser.Status,
		"bio":          updatedUser.Bio,
		"photos":       updatedUser.Photos,
		"birthDate":    updatedUser.BirthDate,
		"gender":       updatedUser.Gender,
		"interestedIn": updatedUser.InterestedIn,
		"referralCode": updatedUser.ReferralCode,
	})
}

func UploadPhoto(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := c.Request.ParseMultipartForm(10 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form data"})
		return
	}

	photoFile, _, err := c.Request.FormFile("photo")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No photo file provided"})
		return
	}
	defer photoFile.Close()

	cld, err := cloudinary.NewFromURL(os.Getenv("CLOUDINARY_URL"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Cloudinary configuration error"})
		return
	}

	uploadParams := uploader.UploadParams{
		Folder:         "coded/photos",
		PublicID:       userID.Hex() + "_" + time.Now().Format("20060102150405"),
		Transformation: "c_limit,w_800,h_800,q_auto",
	}

	uploadResult, err := cld.Upload.Upload(ctx, photoFile, uploadParams)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to upload photo to Cloudinary"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": uploadResult.SecureURL})
}

func GetReferral(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	var user models.User
	err = usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch profile"})
		return
	}

	if user.ReferralCode == "" {
		bytes := make([]byte, 4) // 8 hex characters
		rand.Read(bytes)
		user.ReferralCode = hex.EncodeToString(bytes)
		
		_, updateErr := usersColl.UpdateOne(ctx, bson.M{"_id": userID}, bson.M{"$set": bson.M{"referralCode": user.ReferralCode}})
		if updateErr != nil {
			log.Printf("[GetReferral] Failed to save generated referral code: %v", updateErr)
		}
	}

	baseURL := "https://zukaping.app"
	referralURL := baseURL + "/register?ref=" + user.ReferralCode

	c.JSON(http.StatusOK, gin.H{
		"referralCode": user.ReferralCode,
		"referralUrl":  referralURL,
	})
}

// TestAuth - Simple endpoint to test authentication
func TestAuth(c *gin.Context) {
	userIDStr := c.GetString("userId")
	
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Not authenticated",
			"message": "No user ID in context",
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": "Authentication successful",
		"userId":  userIDStr,
		"time":    time.Now().Unix(),
	})
}

// UpdateUserStatus - Update user status (available, busy, offline)
func UpdateUserStatus(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	var req struct {
		Status string `json:"status" binding:"required,oneof=available busy offline"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	result, err := usersColl.UpdateOne(
		ctx,
		bson.M{"_id": userID},
		bson.M{"$set": bson.M{
			"status":   req.Status,
			"lastSeen": time.Now().Unix(),
		}},
	)

	if err != nil {
		log.Printf("[UpdateUserStatus] Database error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update status"})
		return
	}

	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Status updated successfully",
		"status":  req.Status,
	})
}

func GetMatches(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "GetMatches - not implemented"})
}

// BlockUser - Add target user to current user's blocked list
func BlockUser(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
		return
	}

	targetID, err := primitive.ObjectIDFromHex(req.TargetUserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	// Use $addToSet to prevent duplicates
	_, err = usersColl.UpdateOne(
		ctx,
		bson.M{"_id": userID},
		bson.M{"$addToSet": bson.M{"blockedUsers": targetID}},
	)

	if err != nil {
		log.Printf("[BlockUser] Database error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to block user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User blocked successfully"})
}

// SearchUsers - Search for users by name
func SearchUsers(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusOK, []models.User{})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	usersColl := database.Client.Database("coded").Collection("users")

	// Case-insensitive regex search on the name field
	filter := bson.M{
		"name": bson.M{"$regex": query, "$options": "i"},
	}

	cursor, err := usersColl.Find(ctx, filter)
	if err != nil {
		log.Printf("[SearchUsers] Database error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to search users"})
		return
	}
	defer cursor.Close(ctx)

	var users []models.User
	if err = cursor.All(ctx, &users); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse search results"})
		return
	}

	// Return an empty array if nil
	if users == nil {
		users = []models.User{}
	}

	// Sanitize output (don't send passwords, etc.) - handled by the User struct's json tags hopefully
	c.JSON(http.StatusOK, users)
}

// DeleteMyProfile deletes the currently-authenticated user.
func DeleteMyProfile(c *gin.Context) {
	userIDStr := c.GetString("userId")
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Not authenticated",
			"code":    "UNAUTHORIZED",
			"message": "Please log in first",
		})
		return
	}

	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid user ID",
			"code":    "INVALID_ID",
			"message": "User ID format is wrong",
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	coll := database.Client.Database("coded").Collection("users")
	_, err = coll.DeleteOne(ctx, bson.M{"_id": userID})
	if err != nil {
		log.Printf("[DeleteMyProfile] DB error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Database error",
			"code":    "DB_ERROR",
			"message": "Could not delete account",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Account deleted successfully",
	})
}