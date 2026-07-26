package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"

	"coded/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

func (h *Handler) GetChatList(c *gin.Context) {
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
		slog.Error("failed to fetch user for blocked list", "error", err)
		currentUser = &models.User{}
	}
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

	limitStage := bson.D{{Key: "$limit", Value: 50}}
	pipeline := mongo.Pipeline{matchStage, sortStage, lookupStage, addFieldsStage, filterBlockedStage, limitStage, projectStage}

	cursor, err := h.Repos.Chats.Aggregate(ctx, pipeline)
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

	response := make([]map[string]interface{}, len(results))
	for i, r := range results {
		partnerMap := map[string]interface{}{
			"id":     "",
			"name":   "Unknown",
			"avatar": fallbackAvatar,
			"status": "offline",
		}

		if p, ok := r["partner"].(bson.M); ok && p != nil {
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

func (h *Handler) CreateChat(c *gin.Context) {
	var req struct {
		Participants     []string `json:"participants" binding:"required,min=1"`
		IsGroup          bool     `json:"isGroup"`
		GroupName        string   `json:"groupName"`
		GroupDescription string   `json:"groupDescription"`
		GroupAvatar      string   `json:"groupAvatar"`
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	if !req.IsGroup {
		existing, err := h.Repos.Chats.FindExistingDM(ctx, participantIDs)
		if err == nil && existing != nil {
			c.JSON(http.StatusOK, gin.H{"id": existing.ID.Hex()})
			return
		}
		if err != nil && err != mongo.ErrNoDocuments {
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

	if err := h.Repos.Chats.Create(ctx, &newChat); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create chat"})
		return
	}

	chatData := map[string]interface{}{
		"id":            newChat.ID.Hex(),
		"lastMessageAt": newChat.LastMessageAt,
		"isGroup":       newChat.IsGroup,
		"groupName":     newChat.GroupName,
	}

	if !newChat.IsGroup {
		for _, participantID := range participantIDs {
			if participantID != userID {
				partner, err := h.Repos.Users.FindByID(ctx, participantID)
				if err == nil && partner != nil {
					chatData["partner"] = map[string]interface{}{
						"id":     partner.ID.Hex(),
						"name":   partner.Name,
						"avatar": partner.Avatar,
						"status": partner.Status,
					}
				}
				break
			}
		}
	}

	if h.WS != nil {
		h.WS.BroadcastChatCreated(chatData)
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":   newChat.ID.Hex(),
		"chat": chatData,
	})
}

func (h *Handler) GetChat(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

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

	cursor, err := h.Repos.Chats.Aggregate(ctx, pipeline)
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

	partnerMap := map[string]interface{}{
		"id":     "",
		"name":   "Unknown",
		"avatar": fallbackAvatar,
		"status": "offline",
	}

	if p, ok := result["partner"].(bson.M); ok && p != nil {
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

	var stringAdmins []string
	if adminRaw, ok := result["adminIds"].(primitive.A); ok {
		for _, a := range adminRaw {
			if oid, ok := a.(primitive.ObjectID); ok {
				stringAdmins = append(stringAdmins, oid.Hex())
			}
		}
	}
	result["adminIds"] = stringAdmins
	result["id"] = result["_id"]
	delete(result, "_id")

	c.JSON(http.StatusOK, result)
}

func (h *Handler) UpdateGroupChat(c *gin.Context) {
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
		return
	}

	userIDStr := c.GetString("userId")
	userID, err := primitive.ObjectIDFromHex(userIDStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatId)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	if !h.isAdmin(chat, userID) {
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

	if err := h.Repos.Chats.Update(ctx, chatId, bson.M{"$set": update}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Group updated successfully"})
}

func (h *Handler) PromoteToAdmin(c *gin.Context) {
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request data"})
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatId)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	if !h.isAdmin(chat, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can promote other members"})
		return
	}

	if err := h.Repos.Chats.PromoteAdmin(ctx, chatId, targetUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to promote member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member promoted to admin"})
}

func (h *Handler) RemoveGroupMember(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatId)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Chat not found"})
		return
	}

	if !chat.IsGroup {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Chat is not a group"})
		return
	}

	if !h.isAdmin(chat, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only admins can remove members"})
		return
	}

	if targetUserID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "You cannot remove yourself from the group"})
		return
	}

	if err := h.Repos.Chats.RemoveParticipant(ctx, chatId, targetUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove member"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member removed from group"})
}

func (h *Handler) GenerateGroupInviteCode(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatId)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group chat not found"})
		return
	}

	if !h.isAdmin(chat, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only group admins can generate invite links"})
		return
	}

	bytes := make([]byte, 5)
	if _, randErr := rand.Read(bytes); randErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate invite code"})
		return
	}
	code := hex.EncodeToString(bytes)

	if err := h.Repos.Chats.Update(ctx, chatId, bson.M{"$set": bson.M{"inviteCode": code}}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save invite code"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"inviteCode": code})
}

func (h *Handler) GetGroupInfoByInviteCode(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invite code is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByInviteCode(ctx, code)
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

func (h *Handler) JoinGroupByInviteCode(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByInviteCode(ctx, body.InviteCode)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid invite code or group not found"})
		return
	}

	if err := h.Repos.Chats.AddParticipant(ctx, chat.ID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to join group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Successfully joined group",
		"chatId":  chat.ID.Hex(),
	})
}

func (h *Handler) AddGroupMember(c *gin.Context) {
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatId)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group chat not found"})
		return
	}

	if !h.isAdmin(chat, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only group admins can add members directly"})
		return
	}

	if err := h.Repos.Chats.AddParticipant(ctx, chatId, targetUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add member to group"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member successfully added to group"})
}

func (h *Handler) isAdmin(chat *models.Chat, userID primitive.ObjectID) bool {
	for _, adminID := range chat.AdminIDs {
		if adminID == userID {
			return true
		}
	}
	return false
}
