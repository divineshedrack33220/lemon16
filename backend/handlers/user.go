package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"coded/models"

	"github.com/cloudinary/cloudinary-go/v2"
	"github.com/cloudinary/cloudinary-go/v2/api/uploader"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

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

func generateReferralCode() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (h *Handler) GetUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"id":         userIDStr,
			"name":       "Unknown User",
			"avatar":     fallbackAvatar,
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	user, err := h.Repos.Users.FindByID(ctx, userID)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"id":         userID.Hex(),
			"name":       "Unknown User",
			"avatar":     fallbackAvatar,
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

	c.JSON(http.StatusOK, user)
}

func (h *Handler) GetMyProfile(c *gin.Context) {
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
			"message": "User ID is not valid",
		})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	user, err := h.Repos.Users.FindByID(ctx, userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error":   "Profile not found",
			"code":    "NOT_FOUND",
			"message": "User profile does not exist",
		})
		return
	}

	if user.Status == "" {
		user.Status = "offline"
	}
	if user.Photos == nil {
		user.Photos = []string{}
	}
	if user.InterestedIn == nil {
		user.InterestedIn = []string{}
	}

	if user.ReferralCode == "" {
		var code string
		for {
			code, err = generateReferralCode()
			if err != nil {
				break
			}
			count, countErr := h.Repos.Users.CountByField(ctx, "referralCode", code)
			if countErr != nil {
				break
			}
			if count == 0 {
				break
			}
		}

		if code != "" {
			_, err = h.Repos.Users.Update(ctx, userID, bson.M{"$set": bson.M{"referralCode": code}})
			if err == nil {
				user.ReferralCode = code
			}
		}
	}

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

func (h *Handler) UpdateMyProfile(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()

	update := bson.M{"$set": bson.M{}}

	contentType := c.ContentType()

	var rawData map[string]interface{}
	var data OnboardingData

	if contentType == "application/json" {
		if err := c.ShouldBindJSON(&rawData); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON data"})
			return
		}
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

	if contentType != "application/json" {
		avatarFile, _, err := c.Request.FormFile("avatar")
		if err == nil {
			defer avatarFile.Close()

			cld, err := cloudinary.NewFromURL(h.Cfg.CloudinaryURL)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Cloudinary configuration error"})
				return
			}

			uploadResult, err := cld.Upload.Upload(ctx, avatarFile, uploader.UploadParams{
				Folder:         "coded/avatars",
				PublicID:       userID.Hex(),
				Transformation: "c_limit,w_400,h_400,q_auto",
			})
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

	result, err := h.Repos.Users.Update(ctx, userID, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile"})
		return
	}
	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	updatedUser, fetchErr := h.Repos.Users.FindByID(ctx, userID)
	if fetchErr != nil {
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

func (h *Handler) UploadPhoto(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
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

	cld, err := cloudinary.NewFromURL(h.Cfg.CloudinaryURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Cloudinary configuration error"})
		return
	}

	uploadResult, err := cld.Upload.Upload(ctx, photoFile, uploader.UploadParams{
		Folder:         "coded/photos",
		PublicID:       userID.Hex() + "_" + time.Now().Format("20060102150405"),
		Transformation: "c_limit,w_800,h_800,q_auto",
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to upload photo to Cloudinary"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"url": uploadResult.SecureURL})
}

func (h *Handler) GetReferral(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	user, err := h.Repos.Users.FindByID(ctx, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch profile"})
		return
	}

	if user.ReferralCode == "" {
		bytes := make([]byte, 4)
		if _, err := rand.Read(bytes); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate referral code"})
			return
		}
		user.ReferralCode = hex.EncodeToString(bytes)
		h.Repos.Users.Update(ctx, userID, bson.M{"$set": bson.M{"referralCode": user.ReferralCode}})
	}

	referralURL := h.Cfg.ReferralBaseURL + "/register?ref=" + user.ReferralCode

	c.JSON(http.StatusOK, gin.H{
		"referralCode": user.ReferralCode,
		"referralUrl":  referralURL,
	})
}

func (h *Handler) TestAuth(c *gin.Context) {
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

func (h *Handler) UpdateUserStatus(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	result, err := h.Repos.Users.Update(ctx, userID, bson.M{"$set": bson.M{
		"status":   req.Status,
		"lastSeen": time.Now().Unix(),
	}})
	if err != nil {
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

func (h *Handler) GetMatches(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "GetMatches - not implemented"})
}

func (h *Handler) BlockUser(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	_, err = h.Repos.Users.Update(ctx, userID, bson.M{"$addToSet": bson.M{"blockedUsers": targetID}})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to block user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User blocked successfully"})
}

func (h *Handler) SearchUsers(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusOK, []models.User{})
		return
	}

	query = regexp.QuoteMeta(query)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	limit := int64(50)
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = int64(parsed)
		}
	}

	users, err := h.Repos.Users.Search(ctx, bson.M{
		"name": bson.M{"$regex": query, "$options": "i"},
	}, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to search users"})
		return
	}

	if users == nil {
		users = []models.User{}
	}

	c.JSON(http.StatusOK, users)
}

func (h *Handler) DeleteMyProfile(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	if err := h.Repos.Users.Delete(ctx, userID); err != nil {
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

func (h *Handler) GetNearbyUsers(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	currentUser, err := h.Repos.Users.FindByID(ctx, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch current user"})
		return
	}
	if currentUser.BlockedUsers == nil {
		currentUser.BlockedUsers = []primitive.ObjectID{}
	}

	hasLocation := currentUser.Latitude != nil && currentUser.Longitude != nil &&
		*currentUser.Latitude != 0 && *currentUser.Longitude != 0

	blockedFilter := bson.M{
		"_id": bson.M{
			"$ne":  userID,
			"$nin": currentUser.BlockedUsers,
		},
		"blockedUsers": bson.M{"$ne": userID},
	}

	findOptions := options.Find().SetLimit(30)
	allUsers, err := h.Repos.Users.FindWithFilterAndLimit(ctx, blockedFilter, 30, findOptions)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users"})
		return
	}

	var nearbyUsers []map[string]interface{}

	for _, user := range allUsers {
		var distance float64 = 999999
		var distanceStr string = "Nearby"

		if hasLocation && user.Latitude != nil && user.Longitude != nil &&
			*user.Latitude != 0 && *user.Longitude != 0 {
			distance = calculateDistance(*currentUser.Latitude, *currentUser.Longitude, *user.Latitude, *user.Longitude)
			distanceMeters := distance * 1000
			if distanceMeters < 1000 {
				distanceStr = strconv.FormatInt(int64(distanceMeters), 10) + "m away"
			} else {
				distanceStr = strconv.FormatFloat(distance/1000, 'f', 1, 64) + "km away"
			}
		}

		distScore := 0.0
		if distance < 999999 {
			distScore = 100 - (distance / 10)
		}

		prefScore := 0.0
		for _, interest := range currentUser.InterestedIn {
			if user.Gender == interest {
				prefScore = 50.0
				break
			}
		}

		nearbyUsers = append(nearbyUsers, map[string]interface{}{
			"id":       user.ID.Hex(),
			"name":     user.Name,
			"avatar":   user.Avatar,
			"distance": distanceStr,
			"distVal":  distance,
			"status":   user.Status,
			"bio":      user.Bio,
			"score":    distScore + prefScore,
		})
	}

	if len(nearbyUsers) > 30 {
		nearbyUsers = nearbyUsers[:30]
	}

	c.JSON(http.StatusOK, nearbyUsers)
}

func calculateDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return R * c
}
