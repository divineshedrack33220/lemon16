package handlers

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"coded/models"

	"github.com/SherClockHolmes/webpush-go"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

func (h *Handler) GetMessages(c *gin.Context) {
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

	count, err := h.Repos.Chats.CountParticipants(ctx, chatID, userID)
	if err != nil || count == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to chat"})
		return
	}

	limit := int64(100)
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = int64(parsed)
		}
	}

	cursor, err := h.Repos.Messages.FindByChat(ctx, chatID, limit)
	if err != nil {
		slog.Error("get messages aggregate", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch messages"})
		return
	}
	defer cursor.Close(ctx)

	var rawMessages []bson.M
	if err := cursor.All(ctx, &rawMessages); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to decode messages"})
		return
	}

	response := make([]map[string]interface{}, len(rawMessages))
	for i, m := range rawMessages {
		senderProfile := m["senderProfile"]

		senderMap := map[string]interface{}{
			"id":     m["senderId"].(primitive.ObjectID).Hex(),
			"name":   "Unknown",
			"avatar": fallbackAvatar,
		}

		if profile, ok := senderProfile.(bson.M); ok && profile != nil {
			if name, _ := profile["name"].(string); name != "" {
				senderMap["name"] = name
			}
			if avatar, _ := profile["avatar"].(string); avatar != "" {
				senderMap["avatar"] = avatar
			}
		}

		response[i] = map[string]interface{}{
			"id":        m["_id"].(primitive.ObjectID).Hex(),
			"chatId":    m["chatId"].(primitive.ObjectID).Hex(),
			"senderId":  m["senderId"].(primitive.ObjectID).Hex(),
			"sender":    senderMap,
			"content":   m["content"],
			"type":      m["type"],
			"isRead":    m["isRead"],
			"createdAt": m["createdAt"],
		}
	}

	c.JSON(http.StatusOK, response)
}

func (h *Handler) SendMessage(c *gin.Context) {
	var req struct {
		ChatID  string `json:"chatId" binding:"required"`
		Content string `json:"content" binding:"required"`
		Type    string `json:"type,omitempty"`
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

	chatID, err := primitive.ObjectIDFromHex(req.ChatID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	if req.Type == "" {
		req.Type = "text"
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	chat, err := h.Repos.Chats.FindByID(ctx, chatID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to chat"})
		return
	}

	isParticipant := false
	for _, p := range chat.Participants {
		if p == userID {
			isParticipant = true
			break
		}
	}
	if !isParticipant {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to chat"})
		return
	}

	message := models.Message{
		ID:        primitive.NewObjectID(),
		ChatID:    chatID,
		SenderID:  userID,
		Content:   req.Content,
		Type:      req.Type,
		IsRead:    false,
		CreatedAt: time.Now().Unix(),
	}

	if err := h.Repos.Messages.Create(ctx, &message); err != nil {
		slog.Error("send message insert", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send message"})
		return
	}

	_ = h.Repos.Chats.Update(ctx, chatID, bson.M{
		"$set": bson.M{
			"lastMessage":   req.Content,
			"lastMessageAt": message.CreatedAt,
		},
	})

	sender, err := h.Repos.Users.FindByID(ctx, userID)
	if err != nil || sender == nil {
		sender = &models.User{ID: userID}
	}

	wsMessage := map[string]interface{}{
		"id":        message.ID.Hex(),
		"chatId":    message.ChatID.Hex(),
		"senderId":  message.SenderID.Hex(),
		"sender": map[string]interface{}{
			"id":     sender.ID.Hex(),
			"name":   sender.Name,
			"avatar": sender.Avatar,
		},
		"content":   message.Content,
		"type":      message.Type,
		"isRead":    message.IsRead,
		"createdAt": message.CreatedAt,
	}

	if h.WS != nil {
		h.WS.BroadcastNewMessage(wsMessage, req.ChatID)
	}

	go h.sendPushToParticipants(chat.Participants, userID, sender, message)

	c.JSON(http.StatusCreated, gin.H{
		"message": "Message sent",
		"id":      message.ID.Hex(),
	})
}

func (h *Handler) sendPushToParticipants(participants []primitive.ObjectID, senderID primitive.ObjectID, sender *models.User, message models.Message) {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("panic in push notification", "error", r)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for _, participantID := range participants {
		if participantID == senderID {
			continue
		}

		sub, err := h.Repos.Subscriptions.FindByUser(ctx, participantID)
		if err != nil {
			continue
		}

		webpushSub := &webpush.Subscription{
			Endpoint: sub.Endpoint,
			Keys: webpush.Keys{
				P256dh: sub.Keys.P256dh,
				Auth:   sub.Keys.Auth,
			},
		}

		payload := map[string]interface{}{
			"title": sender.Name + " sent a message",
			"body":  message.Content,
			"icon":  sender.Avatar,
		}
		payloadBytes, err := json.Marshal(payload)
		if err != nil {
			continue
		}

		_, err = webpush.SendNotification(payloadBytes, webpushSub, &webpush.Options{
			Subscriber:      "mailto:admin@coded.com",
			VAPIDPrivateKey: h.Cfg.VAPIDPrivateKey,
			TTL:             30,
		})
		if err != nil {
			slog.Error("failed to send push", "user_id", participantID.Hex(), "error", err)
		}
	}
}

func (h *Handler) MarkAsRead(c *gin.Context) {
	messageIDStr := c.Param("id")
	messageID, err := primitive.ObjectIDFromHex(messageIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message ID"})
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

	msg, err := h.Repos.Messages.FindByID(ctx, messageID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Message not found"})
		return
	}

	count, err := h.Repos.Chats.CountParticipants(ctx, msg.ChatID, userID)
	if err != nil || count == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to chat"})
		return
	}

	result, err := h.Repos.Messages.MarkRead(ctx, msg.ChatID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark as read"})
		return
	}

	if h.WS != nil && result.ModifiedCount > 0 {
		messages, err := h.Repos.Messages.FindUnreadByChat(ctx, msg.ChatID, userID)
		if err == nil {
			var messageIds []string
			for _, m := range messages {
				messageIds = append(messageIds, m.ID.Hex())
			}

			h.WS.BroadcastMessageRead(map[string]interface{}{
				"chatId":     msg.ChatID.Hex(),
				"userId":     userID.Hex(),
				"messageIds": messageIds,
				"timestamp":  time.Now().Unix(),
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message":      "Marked as read",
		"updatedCount": result.ModifiedCount,
	})
}

func (h *Handler) SendTypingIndicator(c *gin.Context) {
	var req struct {
		ChatID string `json:"chatId" binding:"required"`
		Typing bool   `json:"typing"`
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

	chatID, err := primitive.ObjectIDFromHex(req.ChatID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid chat ID"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	count, err := h.Repos.Chats.CountParticipants(ctx, chatID, userID)
	if err != nil || count == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to chat"})
		return
	}

	if h.WS != nil {
		typingMsg := map[string]interface{}{
			"chatId":    chatID.Hex(),
			"userId":    userID.Hex(),
			"typing":    req.Typing,
			"timestamp": time.Now().Unix(),
		}

		if req.Typing {
			h.WS.BroadcastTypingStart(typingMsg)
		} else {
			h.WS.BroadcastTypingEnd(typingMsg)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Typing indicator sent",
		"typing":  req.Typing,
	})
}

func (h *Handler) ReactToMessage(c *gin.Context) {
	messageIDStr := c.Param("id")
	messageID, err := primitive.ObjectIDFromHex(messageIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid message ID"})
		return
	}

	var req struct {
		Emoji string `json:"emoji" binding:"required"`
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"reactions." + userID.Hex(): req.Emoji,
		},
	}

	if req.Emoji == "" || req.Emoji == "remove" {
		update = bson.M{
			"$unset": bson.M{
				"reactions." + userID.Hex(): "",
			},
		}
	}

	_, err = h.Repos.Messages.UpdateOne(ctx, bson.M{"_id": messageID}, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update reaction"})
		return
	}

	updatedMsg, err := h.Repos.Messages.FindByID(ctx, messageID)
	if err == nil && h.WS != nil {
		h.WS.BroadcastMessageReaction(map[string]interface{}{
			"messageId": updatedMsg.ID.Hex(),
			"chatId":    updatedMsg.ChatID.Hex(),
			"userId":    userID.Hex(),
			"emoji":     req.Emoji,
			"reactions": updatedMsg.Reactions,
		})
	}

	reactions := map[string]string{}
	if updatedMsg != nil {
		reactions = updatedMsg.Reactions
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Reaction updated",
		"reactions": reactions,
	})
}

// TestHandler - backward compat
func TestHandler(c *gin.Context) {
	c.JSON(200, gin.H{
		"message": "Handlers are working correctly",
		"time":    time.Now().Unix(),
	})
}
