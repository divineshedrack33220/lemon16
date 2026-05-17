package handlers

import (
    "context"
    "fmt"
    "log"
    "math"
    "net/http"
    "time"

    "coded/database"
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

func CreatePost(c *gin.Context) {
    var req CreatePostRequest
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

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    postsColl := database.Client.Database("coded").Collection("posts")

    post := models.Post{
        ID:        primitive.NewObjectID(),
        UserID:    userID,
        Content:   req.Content,
        Media:     req.Media,
        Category:  req.Category,
        CreatedAt: time.Now().Unix(),
    }

    _, err = postsColl.InsertOne(ctx, post)
    if err != nil {
        log.Printf("CreatePost error: %v", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create post"})
        return
    }

    // Broadcast new post via WebSocket
    if wsManager != nil {
        // Get user info for broadcast
        usersColl := database.Client.Database("coded").Collection("users")
        var user models.User
        usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&user)

        wsManager.BroadcastNewRequest(map[string]interface{}{
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

    c.JSON(http.StatusCreated, gin.H{
        "message": "Post created successfully",
        "postId":  post.ID.Hex(),
    })
}

func haversine(lat1, lon1, lat2, lon2 float64) float64 {
    const R = 6371
    dLat := (lat2 - lat1) * math.Pi / 180
    dLon := (lon2 - lon1) * math.Pi / 180
    a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*math.Sin(dLon/2)*math.Sin(dLon/2)
    c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
    return R * c
}

func GetFeed(c *gin.Context) {
    userIDStr := c.GetString("userId")
    userID, err := primitive.ObjectIDFromHex(userIDStr)
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    usersColl := database.Client.Database("coded").Collection("users")

    var currentUser models.User
    err = usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&currentUser)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch current user"})
        return
    }
    if currentUser.BlockedUsers == nil {
        currentUser.BlockedUsers = []primitive.ObjectID{}
    }

    hasLocation := currentUser.Latitude != nil && currentUser.Longitude != nil && *currentUser.Latitude != 0 && *currentUser.Longitude != 0

    postsColl := database.Client.Database("coded").Collection("posts")

    // Optimization: Use aggregation to join users and filter blocked content in one go
    pipeline := mongo.Pipeline{
        // Join with users to get author info and check their blocked list
        {{Key: "$lookup", Value: bson.D{
            {Key: "from", Value: "users"},
            {Key: "localField", Value: "userId"},
            {Key: "foreignField", Value: "_id"},
            {Key: "as", Value: "author"},
        }}},
        {{Key: "$unwind", Value: "$author"}},
        // Filter out:
        // 1. Posts from users I have blocked
        // 2. Posts from users who have blocked me
        {{Key: "$match", Value: bson.M{
            "userId": bson.M{"$nin": currentUser.BlockedUsers},
            "author.blockedUsers": bson.M{"$ne": userID},
        }}},
        {{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
        {{Key: "$limit", Value: 50}},
    }

    cursor, err := postsColl.Aggregate(ctx, pipeline)
    if err != nil {
        log.Printf("GetFeed aggregate error: %v", err)
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

func GetUserPosts(c *gin.Context) {
    userIDStr := c.Param("id")
    userID, err := primitive.ObjectIDFromHex(userIDStr)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    postsColl := database.Client.Database("coded").Collection("posts")

    pipeline := mongo.Pipeline{
        {{Key: "$match", Value: bson.D{{Key: "userId", Value: userID}}}},
        {{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
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

    cursor, err := postsColl.Aggregate(ctx, pipeline)
    if err != nil {
        log.Printf("GetUserPosts aggregate error: %v", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
        return
    }
    defer cursor.Close(ctx)

    var posts []struct {
        models.Post         `bson:",inline"`
        User                *models.User `bson:"user"`
    }
    if err := cursor.All(ctx, &posts); err != nil {
        log.Printf("GetUserPosts decode error: %v", err)
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

func GetMyPosts(c *gin.Context) {
    userIDStr := c.GetString("userId")
    userID, err := primitive.ObjectIDFromHex(userIDStr)
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    postsColl := database.Client.Database("coded").Collection("posts")

    pipeline := mongo.Pipeline{
        {{Key: "$match", Value: bson.D{{Key: "userId", Value: userID}}}},
        {{Key: "$sort", Value: bson.D{{Key: "createdAt", Value: -1}}}},
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

    cursor, err := postsColl.Aggregate(ctx, pipeline)
    if err != nil {
        log.Printf("GetMyPosts aggregate error: %v", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch posts"})
        return
    }
    defer cursor.Close(ctx)

    var posts []struct {
        models.Post         `bson:",inline"`
        User                *models.User `bson:"user"`
    }
    if err := cursor.All(ctx, &posts); err != nil {
        log.Printf("GetMyPosts decode error: %v", err)
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