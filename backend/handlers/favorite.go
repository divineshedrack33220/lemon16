package handlers

import (
	"context"
	"net/http"
	"time"

	"coded/database"
	"coded/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func AddFavorite(c *gin.Context) {
	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	targetID, err := primitive.ObjectIDFromHex(req.TargetUserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
		return
	}

	if userID == targetID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot favorite yourself"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	favColl := database.Client.Database("coded").Collection("favorites")

	// Check if already favorited
	count, err := favColl.CountDocuments(ctx, bson.M{
		"userId":       userID,
		"targetUserId": targetID,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "Already favorited"})
		return
	}

	fav := models.Favorite{
		ID:           primitive.NewObjectID(),
		UserID:       userID,
		TargetUserID: targetID,
		CreatedAt:    time.Now().Unix(),
	}

	_, err = favColl.InsertOne(ctx, fav)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add favorite"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Favorite added"})
}

func RemoveFavorite(c *gin.Context) {
	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}
	
	// Try to parse from query parameter first (for backward compatibility)
	targetUserId := c.Query("targetUserId")
	if targetUserId == "" {
		// If not in query, try to parse from JSON body
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "targetUserId is required"})
			return
		}
		targetUserId = req.TargetUserID
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	targetID, err := primitive.ObjectIDFromHex(targetUserId)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	favColl := database.Client.Database("coded").Collection("favorites")

	result, err := favColl.DeleteOne(ctx, bson.M{
		"userId":       userID,
		"targetUserId": targetID,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove favorite"})
		return
	}

	if result.DeletedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Favorite not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Favorite removed"})
}

func GetFavorites(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	favColl := database.Client.Database("coded").Collection("favorites")
	usersColl := database.Client.Database("coded").Collection("users")

	// Fetch favorites - FIXED: Use keyed fields in bson.D
	findOptions := options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}})
	cursor, err := favColl.Find(ctx, bson.M{"userId": userID}, findOptions)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch favorites"})
		return
	}
	defer cursor.Close(ctx)

	var favorites []models.Favorite
	if err := cursor.All(ctx, &favorites); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode favorites"})
		return
	}

	if len(favorites) == 0 {
		c.JSON(http.StatusOK, []map[string]interface{}{})
		return
	}

	// Collect target user IDs
	var targetIDs []primitive.ObjectID
	for _, f := range favorites {
		targetIDs = append(targetIDs, f.TargetUserID)
	}

	// Fetch user documents
	userCursor, err := usersColl.Find(ctx, bson.M{"_id": bson.M{"$in": targetIDs}})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users"})
		return
	}
	defer userCursor.Close(ctx)

	var users []models.User
	if err := userCursor.All(ctx, &users); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode users"})
		return
	}

	// Fetch current user for blocked list
	var currentUser models.User
	usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&currentUser)
	if currentUser.BlockedUsers == nil {
		currentUser.BlockedUsers = []primitive.ObjectID{}
	}

	userMap := make(map[primitive.ObjectID]map[string]interface{})
	for _, u := range users {
		// Filter out blocked users
		isBlocked := false
		for _, bID := range currentUser.BlockedUsers {
			if bID == u.ID {
				isBlocked = true
				break
			}
		}
		if isBlocked {
			continue
		}

		// Calculate live online status (active in last 5 mins)
		isOnline := u.Status == "available" || (u.LastSeen > time.Now().Unix()-300)

		userMap[u.ID] = map[string]interface{}{
			"id":       u.ID.Hex(),
			"name":     u.Name,
			"avatar":   u.Avatar,
			"status":   u.Status,
			"isOnline": isOnline,
			"bio":      u.Bio,
		}
	}

	// Use the global fallbackAvatar from common.go
	var response []map[string]interface{}
	for _, f := range favorites {
		if storedUser, exists := userMap[f.TargetUserID]; exists {
			response = append(response, map[string]interface{}{
				"id":           f.ID.Hex(),
				"targetUserId": f.TargetUserID.Hex(),
				"createdAt":    f.CreatedAt,
				"user":         storedUser,
			})
		}
	}

	c.JSON(http.StatusOK, response)
}