package handlers

import (
    "context"
	"fmt"
    "log"
    "math"
    "net/http"
    "sort"
    "time"

    "coded/database"
    "coded/models"

    "github.com/gin-gonic/gin"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/bson/primitive"
    "go.mongodb.org/mongo-driver/mongo/options"
)

func GetNearbyUsers(c *gin.Context) {
    log.Printf("[GetNearbyUsers] Request received")
    
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

    hasLocation := currentUser.Latitude != nil && currentUser.Longitude != nil &&
        *currentUser.Latitude != 0 && *currentUser.Longitude != 0

    // Filter out:
    // 1. Myself
    // 2. Users I have blocked
    // 3. Users who have blocked me
    blockedFilter := bson.M{
        "_id": bson.M{
            "$ne":  userID,
            "$nin": currentUser.BlockedUsers,
        },
        "blockedUsers": bson.M{"$ne": userID},
    }

    // Get a limited sample of users to reduce server stress
    findOptions := options.Find().SetLimit(30)
    cursor, err := usersColl.Find(ctx, blockedFilter, findOptions)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users"})
        return
    }
    defer cursor.Close(ctx)

    var allUsers []models.User
    if err = cursor.All(ctx, &allUsers); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode users"})
        return
    }

    var nearbyUsers = []map[string]interface{}{}

    for _, user := range allUsers {
        var distance float64 = 999999 // Default for no location
        var distanceStr string = "Nearby"
        
        if hasLocation && user.Latitude != nil && user.Longitude != nil &&
            *user.Latitude != 0 && *user.Longitude != 0 {
            distance = calculateDistance(*currentUser.Latitude, *currentUser.Longitude, *user.Latitude, *user.Longitude)
            distanceMeters := math.Round(distance * 1000)
            if distanceMeters < 1000 {
                distanceStr = fmt.Sprintf("%.0fm away", distanceMeters)
            } else {
                distanceStr = fmt.Sprintf("%.1fkm away", distance/1000)
            }
        }

        // Calculate a "Match Score"
        // Higher is better. 
        // 1. Distance score (max 100 points, closer is better)
        distScore := math.Max(0, 100 - (distance / 10)) 
        
        // 2. Preference score (max 50 points)
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

    // Sort by score (descending)
    sort.Slice(nearbyUsers, func(i, j int) bool {
        return nearbyUsers[i]["score"].(float64) > nearbyUsers[j]["score"].(float64)
    })

    // Take top 30
    if len(nearbyUsers) > 30 {
        nearbyUsers = nearbyUsers[:30]
    }

    log.Printf("[GetNearbyUsers] Returning %d ranked users", len(nearbyUsers))
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
