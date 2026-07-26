package handlers

import (
	"context"
	"net/http"
	"time"

	"coded/notify"
	"coded/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

func (h *Handler) AddFavorite(c *gin.Context) {
	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	exists, err := h.Repos.Favorites.Exists(ctx, userID, targetID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "Already favorited"})
		return
	}

	fav := models.Favorite{
		ID:           primitive.NewObjectID(),
		UserID:       userID,
		TargetUserID: targetID,
		CreatedAt:    time.Now().Unix(),
	}

	if err := h.Repos.Favorites.Create(ctx, &fav); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add favorite"})
		return
	}

	target, _ := h.Repos.Users.FindByID(ctx, targetID)

	if target != nil {
		h.Notifier.OnFavorite(c.Request.Context(), notify.FavoriteNotification{
			FavoriterID:   userID.Hex(),
			FavoriterName: getUserDisplayName(h, ctx, userID),
			TargetID:      targetID.Hex(),
			TargetEmail:   target.Email,
			TargetPhone:   target.Phone,
		})
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Favorite added"})
}

func (h *Handler) RemoveFavorite(c *gin.Context) {
	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}

	targetUserId := c.Query("targetUserId")
	if targetUserId == "" {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	result, err := h.Repos.Favorites.Delete(ctx, userID, targetID)
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

func (h *Handler) GetFavorites(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	favorites, err := h.Repos.Favorites.FindByUser(ctx, userID, 100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch favorites"})
		return
	}

	if len(favorites) == 0 {
		c.JSON(http.StatusOK, []map[string]interface{}{})
		return
	}

	var targetIDs []primitive.ObjectID
	for _, f := range favorites {
		targetIDs = append(targetIDs, f.TargetUserID)
	}

	users, err := h.Repos.Users.FindMany(ctx, bson.M{"_id": bson.M{"$in": targetIDs}})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users"})
		return
	}

	currentUser, _ := h.Repos.Users.FindByID(ctx, userID)
	if currentUser == nil {
		currentUser = &models.User{}
	}
	if currentUser.BlockedUsers == nil {
		currentUser.BlockedUsers = []primitive.ObjectID{}
	}

	userMap := make(map[primitive.ObjectID]map[string]interface{})
	for _, u := range users {
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

func getUserDisplayName(h *Handler, ctx context.Context, id primitive.ObjectID) string {
	user, err := h.Repos.Users.FindByID(ctx, id)
	if err != nil || user == nil {
		return "Someone"
	}
	if user.Name != "" {
		return user.Name
	}
	if user.Username != "" {
		return user.Username
	}
	return "Someone"
}
