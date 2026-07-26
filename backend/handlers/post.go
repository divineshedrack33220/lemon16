package handlers

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"coded/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type CreatePostRequest struct {
	Content  string   `json:"content" binding:"required"`
	Media    []string `json:"media"`
	Category string   `json:"category,omitempty"`
}

func (h *Handler) CreatePost(c *gin.Context) {
	var req CreatePostRequest
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	post := models.Post{
		ID:        primitive.NewObjectID(),
		UserID:    userID,
		Content:   req.Content,
		Media:     req.Media,
		Category:  req.Category,
		CreatedAt: time.Now().Unix(),
	}

	if err := h.Repos.Posts.Create(ctx, &post); err != nil {
		slog.Error("create post", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create post"})
		return
	}

	if h.WS != nil {
		user, err := h.Repos.Users.FindByID(ctx, userID)
		if err == nil && user != nil {
			h.WS.BroadcastNewRequest(map[string]interface{}{
				"id":        post.ID.Hex(),
				"userId":    user.ID.Hex(),
				"content":   post.Content,
				"media":     post.Media,
				"category":  post.Category,
				"createdAt": post.CreatedAt,
				"user": map[string]interface{}{
					"id":     user.ID.Hex(),
					"name":   user.Name,
					"avatar": user.Avatar,
				},
			})
		}
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Post created successfully",
		"postId":  post.ID.Hex(),
	})
}

func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	return calculateDistance(lat1, lon1, lat2, lon2)
}

func (h *Handler) GetFeed(c *gin.Context) {
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

	hasLocation := currentUser.Latitude != nil && currentUser.Longitude != nil && *currentUser.Latitude != 0 && *currentUser.Longitude != 0

	pipeline := mongo.Pipeline{
		{{Key: "$lookup", Value: bson.D{
			{Key: "from", Value: "users"},
			{Key: "localField", Value: "userId"},
			{Key: "foreignField", Value: "_id"},
			{Key: "as", Value: "author"},
		}}},
		{{Key: "$unwind", Value: "$author"}},
		{{Key: "$match", Value: bson.M{
			"userId": bson.M{"$nin": currentUser.BlockedUsers},
			"author.blockedUsers": bson.M{"$ne": userID},
		}}},
		{{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
		{{Key: "$limit", Value: 50}},
	}

	cursor, err := h.Repos.Posts.Aggregate(ctx, pipeline)
	if err != nil {
		slog.Error("get feed aggregate", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch feed"})
		return
	}
	defer cursor.Close(ctx)

	var result []map[string]interface{}
	for cursor.Next(ctx) {
		var post struct {
			models.Post `bson:",inline"`
			Author      models.User `bson:"author"`
		}
		if err := cursor.Decode(&post); err != nil {
			continue
		}

		var distStr string
		if !hasLocation {
			distStr = "Nearby"
		} else if post.Author.Latitude == nil || post.Author.Longitude == nil || (*post.Author.Latitude == 0 && *post.Author.Longitude == 0) {
			distStr = "Unknown"
		} else {
			distance := haversine(*currentUser.Latitude, *currentUser.Longitude, *post.Author.Latitude, *post.Author.Longitude)
			distStr = fmt.Sprintf("%.0f km away", distance)
		}

		result = append(result, map[string]interface{}{
			"id":        post.ID.Hex(),
			"user":      post.Author,
			"content":   post.Content,
			"category":  post.Category,
			"media":     post.Media,
			"createdAt": post.CreatedAt,
			"distance":  distStr,
		})
	}

	c.JSON(http.StatusOK, result)
}

func (h *Handler) GetUserPosts(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.D{{Key: "userId", Value: userID}}}},
		{{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
		{{Key: "$limit", Value: 50}},
		{{Key: "$lookup", Value: bson.D{
			{Key: "from", Value: "users"},
			{Key: "localField", Value: "userId"},
			{Key: "foreignField", Value: "_id"},
			{Key: "as", Value: "user"},
		}}},
		{{Key: "$unwind", Value: bson.D{
			{Key: "path", Value: "$user"},
			{Key: "preserveNullAndEmptyArrays", Value: true},
		}}},
	}

	cursor, err := h.Repos.Posts.Aggregate(ctx, pipeline)
	if err != nil {
		slog.Error("get user posts aggregate", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
		return
	}
	defer cursor.Close(ctx)

	var posts []struct {
		models.Post `bson:",inline"`
		User        *models.User `bson:"user"`
	}
	if err := cursor.All(ctx, &posts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode posts"})
		return
	}

	response := make([]map[string]interface{}, len(posts))
	for i, p := range posts {
		userMap := map[string]interface{}{
			"id":     p.UserID.Hex(),
			"name":   "Unknown User",
			"avatar": fallbackAvatar,
			"status": "offline",
			"bio":    "",
		}

		if p.User != nil {
			if p.User.Name != "" {
				userMap["name"] = p.User.Name
			}
			if p.User.Avatar != "" {
				userMap["avatar"] = p.User.Avatar
			}
			if p.User.Status != "" {
				userMap["status"] = p.User.Status
			}
			if p.User.Bio != "" {
				userMap["bio"] = p.User.Bio
			}
		}

		response[i] = map[string]interface{}{
			"id":        p.ID.Hex(),
			"content":   p.Content,
			"media":     p.Media,
			"category":  p.Category,
			"createdAt": p.CreatedAt,
			"user":      userMap,
		}
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handler) GetMyPosts(c *gin.Context) {
	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.D{{Key: "userId", Value: userID}}}},
		{{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
		{{Key: "$limit", Value: 50}},
		{{Key: "$lookup", Value: bson.D{
			{Key: "from", Value: "users"},
			{Key: "localField", Value: "userId"},
			{Key: "foreignField", Value: "_id"},
			{Key: "as", Value: "user"},
		}}},
		{{Key: "$unwind", Value: bson.D{
			{Key: "path", Value: "$user"},
			{Key: "preserveNullAndEmptyArrays", Value: true},
		}}},
	}

	cursor, err := h.Repos.Posts.Aggregate(ctx, pipeline)
	if err != nil {
		slog.Error("get my posts aggregate", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
		return
	}
	defer cursor.Close(ctx)

	var posts []struct {
		models.Post `bson:",inline"`
		User        *models.User `bson:"user"`
	}
	if err := cursor.All(ctx, &posts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode posts"})
		return
	}

	response := make([]map[string]interface{}, len(posts))
	for i, p := range posts {
		userMap := map[string]interface{}{
			"id":     p.UserID.Hex(),
			"name":   "Unknown User",
			"avatar": fallbackAvatar,
			"status": "offline",
			"bio":    "",
		}

		if p.User != nil {
			if p.User.Name != "" {
				userMap["name"] = p.User.Name
			}
			if p.User.Avatar != "" {
				userMap["avatar"] = p.User.Avatar
			}
			if p.User.Status != "" {
				userMap["status"] = p.User.Status
			}
			if p.User.Bio != "" {
				userMap["bio"] = p.User.Bio
			}
		}

		response[i] = map[string]interface{}{
			"id":        p.ID.Hex(),
			"content":   p.Content,
			"media":     p.Media,
			"category":  p.Category,
			"createdAt": p.CreatedAt,
			"user":      userMap,
		}
	}

	c.JSON(http.StatusOK, response)
}
