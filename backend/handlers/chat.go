package handlers

import (
    "context"
    "crypto/rand"
    "encoding/hex"
    "net/http"
    "time"

    "coded/database"
    "coded/models"

    "github.com/gin-gonic/gin"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/bson/primitive"
    "go.mongodb.org/mongo-driver/mongo"
)

func GetChatList(c *gin.Context) {
    userIDStr := c.GetString("userId")
    userID, err := primitive.ObjectIDFromHex(userIDStr)
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    chatsColl := database.Client.Database("coded").Collection("chats")

    // Build pipeline step by step to avoid nested bson.D issues
    // Fetch current user's blocked list first
    usersColl := database.Client.Database("coded").Collection("users")
    var currentUser models.User
    usersColl.FindOne(ctx, bson.M{"_id": userID}).Decode(&currentUser)
    if currentUser.BlockedUsers == nil {
        currentUser.BlockedUsers = []primitive.ObjectID{}
    }

    matchStage := bson.D{{Key: "$match", Value: bson.D{{Key: "participants", Value: userID}}}}
    sortStage := bson.D{{Key: "$sort", Value: bson.D{{Key: "lastMessageAt", Value: -1}}}}
    
    lookupStage := bson.D{{Key: "$lookup", Value: bson.D{
        {Key: "from", Value: "users"},
        {Key: "localField", Value: "participants"},
        {Key: "foreignField", Value: "_id"},
        {Key: "as", Value: "participantsProfiles"},
    }}}
    
    // Add logic to identify the partner
    addFieldsStage := bson.D{{Key: "$addFields", Value: bson.D{
        {Key: "partner", Value: bson.D{
            {Key: "$arrayElemAt", Value: bson.A{
                bson.D{{Key: "$filter", Value: bson.D{
                    {Key: "input", Value: "$participantsProfiles"},
                    {Key: "as", Value: "p"},
                    {Key: "cond", Value: bson.D{{Key: "$ne", Value: bson.A{"$$p._id", userID}}}},
                }}}, 
                0,
            }},
        }},
    }}}

    // FILTER OUT BLOCKED CHATS
    // 1. Partner is in my BlockedUsers
    // 2. I am in Partner's BlockedUsers
    filterBlockedStage := bson.D{{Key: "$match", Value: bson.D{
        {Key: "partner._id", Value: bson.D{{Key: "$nin", Value: currentUser.BlockedUsers}}},
        {Key: "partner.blockedUsers", Value: bson.D{{Key: "$ne", Value: userID}}},
    }}}
    
    projectStage := bson.D{{Key: "$project", Value: bson.D{
        {Key: "id", Value: "$_id"},
        {Key: "lastMessage", Value: 1},
        {Key: "lastMessageAt", Value: 1},
        {Key: "isGroup", Value: 1},
        {Key: "groupName", Value: 1},
        {Key: "groupAvatar", Value: 1},
        {Key: "groupDescription", Value: 1},
        {Key: "adminIds", Value: 1},
        {Key: "inviteCode", Value: 1},
        {Key: "participantsProfiles", Value: bson.D{
            {Key: "$map", Value: bson.D{
                {Key: "input", Value: "$participantsProfiles"},
                {Key: "as", Value: "p"},
                {Key: "in", Value: bson.D{
                    {Key: "id", Value: "$$p._id"},
                    {Key: "name", Value: "$$p.name"},
                    {Key: "avatar", Value: "$$p.avatar"},
                    {Key: "status", Value: "$$p.status"},
                }},
            }},
        }},
        {Key: "partner", Value: bson.D{
            {Key: "id", Value: "$partner._id"},
            {Key: "name", Value: "$partner.name"},
            {Key: "avatar", Value: "$partner.avatar"},
            {Key: "status", Value: "$partner.status"},
        }},
    }}}

    pipeline := mongo.Pipeline{matchStage, sortStage, lookupStage, addFieldsStage, filterBlockedStage, projectStage}

    cursor, err := chatsColl.Aggregate(ctx, pipeline)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch chats"})
        return
    }
    defer cursor.Close(ctx)

    var results []bson.M
    if err := cursor.All(ctx, &results); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode chats"})
        return
    }

    // Ensure partner is always a valid object with fallback values
    response := make([]map[string]interface{}, len(results))
    for i, r := range results {
        partnerRaw := r["partner"]
        partnerMap := map[string]interface{}{
            "id":     "",
            "name":   "Unknown",
            "avatar": fallbackAvatar,
            "status": "offline",
        }

        if p, ok := partnerRaw.(bson.M); ok && p != nil {
            if id, _ := p["_id"].(primitive.ObjectID); id != primitive.NilObjectID {
                partnerMap["id"] = id.Hex()
            }
            if name, _ := p["name"].(string); name != "" {
                partnerMap["name"] = name
            }
            if avatar, _ := p["avatar"].(string); avatar != "" {
                partnerMap["avatar"] = avatar
            }
            if status, _ := p["status"].(string); status != "" {
                partnerMap["status"] = status
            }
        }

        // Format adminIds to Hex string array
        var stringAdmins []string
        if adminRaw, ok := r["adminIds"].(primitive.A); ok {
            for _, a := range adminRaw {
                if oid, ok := a.(primitive.ObjectID); ok {
                    stringAdmins = append(stringAdmins, oid.Hex())
                }
            }
        }

        response[i] = map[string]interface{}{
            "id":                   r["id"],
            "lastMessage":          r["lastMessage"],
            "lastMessageAt":        r["lastMessageAt"],
            "isGroup":              r["isGroup"],
            "groupName":            r["groupName"],
            "groupAvatar":          r["groupAvatar"],
            "groupDescription":     r["groupDescription"],
            "adminIds":             stringAdmins,
            "inviteCode":           r["inviteCode"],
            "participantsProfiles": r["participantsProfiles"],
            "partner":              partnerMap,
        }
    }

    c.JSON(http.StatusOK, response)
}

func CreateChat(c *gin.Context) {
    var req struct {
        Participants     []string `json:"participants" binding:"required,min=1"`
        IsGroup          bool     `json:"isGroup"`
        GroupName        string   `json:"groupName"`
        GroupDescription string   `json:"groupDescription"`
        GroupAvatar      string   `json:"groupAvatar"`
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

    var participantIDs []primitive.ObjectID
    participantIDs = append(participantIDs, userID)

    for _, p := range req.Participants {
        pID, err := primitive.ObjectIDFromHex(p)
        if err != nil {
            c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid participant ID"})
            return
        }
        if pID != userID {
            participantIDs = append(participantIDs, pID)
        }
    }

    if len(participantIDs) < 2 {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Chat must have at least two participants"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    chatsColl := database.Client.Database("coded").Collection("chats")

    // Only check for existing chats if it's NOT a group chat
    if !req.IsGroup {
        filter := bson.M{
            "participants": bson.M{
                "$all":  participantIDs,
                "$size": len(participantIDs),
            },
            "isGroup": bson.M{"$ne": true},
        }

        var existingChat models.Chat
        err = chatsColl.FindOne(ctx, filter).Decode(&existingChat)
        if err == nil {
            c.JSON(http.StatusOK, gin.H{
                "id": existingChat.ID.Hex(),
            })
            return
        }
        if err != mongo.ErrNoDocuments {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
            return
        }
    }

    var adminIds []primitive.ObjectID
    if req.IsGroup {
        adminIds = []primitive.ObjectID{userID}
    }

    newChat := models.Chat{
        ID:               primitive.NewObjectID(),
        Participants:     participantIDs,
        LastMessageAt:    time.Now().Unix(),
        CreatedAt:        time.Now().Unix(),
        IsGroup:          req.IsGroup,
        GroupName:        req.GroupName,
        GroupDescription: req.GroupDescription,
        GroupAvatar:      req.GroupAvatar,
        AdminIDs:         adminIds,
    }

    _, err = chatsColl.InsertOne(ctx, newChat)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create chat"})
        return
    }

    // Determine partner info or group info for WebSocket
    chatData := map[string]interface{}{
        "id":            newChat.ID.Hex(),
        "lastMessageAt": newChat.LastMessageAt,
        "isGroup":       newChat.IsGroup,
        "groupName":     newChat.GroupName,
    }

    if !newChat.IsGroup {
        usersColl := database.Client.Database("coded").Collection("users")
        var partner models.User
        for _, participantID := range participantIDs {
            if participantID != userID {
                usersColl.FindOne(ctx, bson.M{"_id": participantID}).Decode(&partner)
                break
            }
        }
        chatData["partner"] = map[string]interface{}{
            "id":     partner.ID.Hex(),
            "name":   partner.Name,
            "avatar": partner.Avatar,
            "status": partner.Status,
        }
    }

    // Broadcast new chat creation via WebSocket
    if wsManager != nil {
        wsManager.BroadcastChatCreated(chatData)
    }

    c.JSON(http.StatusCreated, gin.H{
        "id":   newChat.ID.Hex(),
        "chat": chatData,
    })
}

func GetChat(c *gin.Context) {
    chatIDStr := c.Param("id")
    chatID, err := primitive.ObjectIDFromHex(chatIDStr)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
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

    chatsColl := database.Client.Database("coded").Collection("chats")

    // Build pipeline step by step
    matchStage := bson.D{{Key: "$match", Value: bson.D{
        {Key: "_id", Value: chatID},
        {Key: "participants", Value: userID},
    }}}
    
    lookupStage := bson.D{{Key: "$lookup", Value: bson.D{
        {Key: "from", Value: "users"},
        {Key: "localField", Value: "participants"},
        {Key: "foreignField", Value: "_id"},
        {Key: "as", Value: "participantsProfiles"},
    }}}
    
    filterCond := bson.D{{Key: "$filter", Value: bson.D{
        {Key: "input", Value: "$participantsProfiles"},
        {Key: "as", Value: "p"},
        {Key: "cond", Value: bson.D{{Key: "$ne", Value: bson.A{"$$p._id", userID}}}},
    }}}
    
    addFieldsStage := bson.D{{Key: "$addFields", Value: bson.D{
        {Key: "partner", Value: bson.D{
            {Key: "$arrayElemAt", Value: bson.A{filterCond, 0}},
        }},
    }}}
    
    projectStage := bson.D{{Key: "$project", Value: bson.D{
        {Key: "id", Value: "$_id"},
        {Key: "lastMessage", Value: 1},
        {Key: "lastMessageAt", Value: 1},
        {Key: "isGroup", Value: 1},
        {Key: "groupName", Value: 1},
        {Key: "groupAvatar", Value: 1},
        {Key: "groupDescription", Value: 1},
        {Key: "adminIds", Value: 1},
        {Key: "inviteCode", Value: 1},
        {Key: "participantsProfiles", Value: bson.D{
            {Key: "$map", Value: bson.D{
                {Key: "input", Value: "$participantsProfiles"},
                {Key: "as", Value: "p"},
                {Key: "in", Value: bson.D{
                    {Key: "id", Value: "$$p._id"},
                    {Key: "name", Value: "$$p.name"},
                    {Key: "avatar", Value: "$$p.avatar"},
                    {Key: "status", Value: "$$p.status"},
                }},
            }},
        }},
        {Key: "partner", Value: bson.D{
            {Key: "id", Value: "$partner._id"},
            {Key: "name", Value: "$partner.name"},
            {Key: "avatar", Value: "$partner.avatar"},
            {Key: "status", Value: "$partner.status"},
        }},
    }}}

    pipeline := mongo.Pipeline{matchStage, lookupStage, addFieldsStage, projectStage}

    cursor, err := chatsColl.Aggregate(ctx, pipeline)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch chat"})
        return
    }
    defer cursor.Close(ctx)

    if !cursor.Next(ctx) {
        c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found or access denied"})
        return
    }

    var result bson.M
    if err := cursor.Decode(&result); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode chat"})
        return
    }

    // Apply fallback for partner
    partnerRaw := result["partner"]
    partnerMap := map[string]interface{}{
        "id":     "",
        "name":   "Unknown",
        "avatar": fallbackAvatar,
        "status": "offline",
    }

    if p, ok := partnerRaw.(bson.M); ok && p != nil {
        if id, _ := p["_id"].(primitive.ObjectID); id != primitive.NilObjectID {
            partnerMap["id"] = id.Hex()
        }
        if name, _ := p["name"].(string); name != "" {
            partnerMap["name"] = name
        }
        if avatar, _ := p["avatar"].(string); avatar != "" {
            partnerMap["avatar"] = avatar
        }
        if status, _ := p["status"].(string); status != "" {
            partnerMap["status"] = status
        }
    }

    result["partner"] = partnerMap

    // Format adminIds to Hex string array
    var stringAdmins []string
    if adminRaw, ok := result["adminIds"].(primitive.A); ok {
        for _, a := range adminRaw {
            if oid, ok := a.(primitive.ObjectID); ok {
                stringAdmins = append(stringAdmins, oid.Hex())
            }
        }
    }
    result["adminIds"] = stringAdmins

    // Fix _id mapping for JSON
    result["id"] = result["_id"]
    delete(result, "_id")

    c.JSON(http.StatusOK, result)
}

func UpdateGroupChat(c *gin.Context) {
	chatIdStr := c.Param("id")
	chatId, err := primitive.ObjectIDFromHex(chatIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	var req struct {
		GroupName        string `json:"groupName"`
		GroupDescription string `json:"groupDescription"`
		GroupAvatar      string `json:"groupAvatar"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	chatsColl := database.Client.Database("coded").Collection("chats")

	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"_id": chatId}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	// Verify caller is admin
	isAdmin := false
	for _, adminId := range chat.AdminIDs {
		if adminId == userID {
			isAdmin = true
			break
		}
	}
	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can edit group details"})
		return
	}

	update := bson.M{}
	if req.GroupName != "" {
		update["groupName"] = req.GroupName
	}
	if req.GroupDescription != "" {
		update["groupDescription"] = req.GroupDescription
	}
	if req.GroupAvatar != "" {
		update["groupAvatar"] = req.GroupAvatar
	}

	if len(update) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No update fields provided"})
		return
	}

	_, err = chatsColl.UpdateOne(ctx, bson.M{"_id": chatId}, bson.M{"$set": update})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Group updated successfully"})
}

func PromoteToAdmin(c *gin.Context) {
	chatIdStr := c.Param("id")
	chatId, err := primitive.ObjectIDFromHex(chatIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	var req struct {
		TargetUserID string `json:"targetUserId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	targetUserID, err := primitive.ObjectIDFromHex(req.TargetUserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
		return
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	chatsColl := database.Client.Database("coded").Collection("chats")

	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"_id": chatId}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	// Verify caller is admin
	isAdmin := false
	for _, adminId := range chat.AdminIDs {
		if adminId == userID {
			isAdmin = true
			break
		}
	}
	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can promote other members"})
		return
	}

	// Add target user to admins
	_, err = chatsColl.UpdateOne(ctx, bson.M{"_id": chatId}, bson.M{"$addToSet": bson.M{"adminIds": targetUserID}})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to promote member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member promoted to admin"})
}

func RemoveGroupMember(c *gin.Context) {
	chatIdStr := c.Param("id")
	chatId, err := primitive.ObjectIDFromHex(chatIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	targetUserIdStr := c.Param("userId")
	targetUserID, err := primitive.ObjectIDFromHex(targetUserIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
		return
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	chatsColl := database.Client.Database("coded").Collection("chats")

	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"_id": chatId}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	// Verify caller is admin
	isAdmin := false
	for _, adminId := range chat.AdminIDs {
		if adminId == userID {
			isAdmin = true
			break
		}
	}
	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can remove members"})
		return
	}

	// Prevent removing oneself
	if targetUserID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "You cannot remove yourself from the group"})
		return
	}

	// Pull target user from participants and adminIds
	_, err = chatsColl.UpdateOne(ctx, bson.M{"_id": chatId}, bson.M{
		"$pull": bson.M{
			"participants": targetUserID,
			"adminIds":     targetUserID,
		},
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member removed from group"})
}

// GenerateGroupInviteCode handles generating a group invite code (admin restricted)
func GenerateGroupInviteCode(c *gin.Context) {
	chatIdStr := c.Param("id")
	chatId, err := primitive.ObjectIDFromHex(chatIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
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

	chatsColl := database.Client.Database("coded").Collection("chats")

	// Verify group exists and user is admin
	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"_id": chatId, "isGroup": true}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group chat not found"})
		return
	}

	isAdmin := false
	for _, adminID := range chat.AdminIDs {
		if adminID == userID {
			isAdmin = true
			break
		}
	}

	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only group admins can generate invite links"})
		return
	}

	// Generate a unique 10-char hex code
	bytes := make([]byte, 5)
	if _, randErr := rand.Read(bytes); randErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate invite code"})
		return
	}
	code := hex.EncodeToString(bytes)

	// Save code to the group chat
	_, err = chatsColl.UpdateOne(ctx, bson.M{"_id": chatId}, bson.M{"$set": bson.M{"inviteCode": code}})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save invite code"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"inviteCode": code,
	})
}

// GetGroupInfoByInviteCode fetches public group information by invite code (PUBLIC endpoint)
func GetGroupInfoByInviteCode(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invite code is required"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	chatsColl := database.Client.Database("coded").Collection("chats")

	var chat models.Chat
	err := chatsColl.FindOne(ctx, bson.M{"inviteCode": code, "isGroup": true}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid invite link or group not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":               chat.ID.Hex(),
		"groupName":        chat.GroupName,
		"groupAvatar":      chat.GroupAvatar,
		"groupDescription": chat.GroupDescription,
		"memberCount":      len(chat.Participants),
	})
}

// JoinGroupByInviteCode registers an authenticated user into the group chat using an invite code
func JoinGroupByInviteCode(c *gin.Context) {
	var body struct {
		InviteCode string `json:"inviteCode" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invite code is required"})
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

	chatsColl := database.Client.Database("coded").Collection("chats")

	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"inviteCode": body.InviteCode, "isGroup": true}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid invite code or group not found"})
		return
	}

	// Add user to participants if not already there
	_, err = chatsColl.UpdateOne(ctx,
		bson.M{"_id": chat.ID},
		bson.M{"$addToSet": bson.M{"participants": userID}},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to join group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Successfully joined group",
		"chatId":  chat.ID.Hex(),
	})
}

// AddGroupMember allows group admins to manually add existing registered users directly to the group
func AddGroupMember(c *gin.Context) {
	chatIdStr := c.Param("id")
	chatId, err := primitive.ObjectIDFromHex(chatIdStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	var body struct {
		UserID string `json:"userId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "User ID to add is required"})
		return
	}

	targetUserID, err := primitive.ObjectIDFromHex(body.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid target user ID"})
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

	chatsColl := database.Client.Database("coded").Collection("chats")

	// Verify group exists and caller is admin
	var chat models.Chat
	err = chatsColl.FindOne(ctx, bson.M{"_id": chatId, "isGroup": true}).Decode(&chat)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group chat not found"})
		return
	}

	isAdmin := false
	for _, adminID := range chat.AdminIDs {
		if adminID == userID {
			isAdmin = true
			break
		}
	}

	if !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only group admins can add members directly"})
		return
	}

	// Add target user to participants
	_, err = chatsColl.UpdateOne(ctx,
		bson.M{"_id": chatId},
		bson.M{"$addToSet": bson.M{"participants": targetUserID}},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add member to group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Member successfully added to group",
	})
}
