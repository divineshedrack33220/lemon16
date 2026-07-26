package handlers

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"coded/models"

	"github.com/gin-gonic/gin"
	"github.com/SherClockHolmes/webpush-go"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

var vapidPrivateKey string

func InitVAPIDKeys() {
	if os.Getenv("VAPID_PUBLIC_KEY") == "" || os.Getenv("VAPID_PRIVATE_KEY") == "" {
		publicKey, privateKey, err := webpush.GenerateVAPIDKeys()
		if err != nil {
			slog.Error("failed to generate VAPID keys", "error", err)
			return
		}

		os.Setenv("VAPID_PUBLIC_KEY", publicKey)
		vapidPrivateKey = privateKey

		slog.Warn("generated new VAPID keys - set as environment variables for production")
	} else {
		vapidPrivateKey = os.Getenv("VAPID_PRIVATE_KEY")
		slog.Info("VAPID keys loaded from environment")
	}
}

func (h *Handler) GetVapidPublicKey(c *gin.Context) {
	publicKey := os.Getenv("VAPID_PUBLIC_KEY")
	if publicKey == "" {
		c.JSON(http.StatusOK, gin.H{
			"error":   "VAPID public key not configured",
			"message": "Contact administrator",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"publicKey": publicKey,
		"message":   "VAPID public key retrieved successfully",
	})
}

func (h *Handler) SubscribePush(c *gin.Context) {
	var req struct {
		Endpoint string `json:"endpoint" binding:"required"`
		Keys     struct {
			P256dh string `json:"p256dh" binding:"required"`
			Auth   string `json:"auth" binding:"required"`
		} `json:"keys" binding:"required"`
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

	pushSub := models.PushSubscription{
		ID:        primitive.NewObjectID(),
		UserID:    userID,
		Endpoint:  req.Endpoint,
		CreatedAt: time.Now().Unix(),
	}
	pushSub.Keys.P256dh = req.Keys.P256dh
	pushSub.Keys.Auth = req.Keys.Auth

	if err := h.Repos.Subscriptions.Upsert(ctx, &pushSub); err != nil {
		slog.Error("failed to save subscription", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save subscription"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Push subscription saved successfully",
		"userId":  userID.Hex(),
	})
}

func (h *Handler) SendPushNotification(userID primitive.ObjectID, title, body, icon string) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Error("panic in push notification", "error", r)
			}
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		sub, err := h.Repos.Subscriptions.FindByUser(ctx, userID)
		if err != nil {
			return
		}

		webpushSub := &webpush.Subscription{
			Endpoint: sub.Endpoint,
			Keys: webpush.Keys{
				P256dh: sub.Keys.P256dh,
				Auth:   sub.Keys.Auth,
			},
		}

		payload := map[string]interface{}{
			"title": title,
			"body":  body,
			"icon":  icon,
			"data": map[string]interface{}{
				"url":       "/chats.html",
				"timestamp": time.Now().Unix(),
			},
		}

		payloadBytes, err := json.Marshal(payload)
		if err != nil {
			return
		}

		resp, err := webpush.SendNotification(payloadBytes, webpushSub, &webpush.Options{
			Subscriber:      "mailto:admin@coded.com",
			VAPIDPrivateKey: h.Cfg.VAPIDPrivateKey,
			TTL:             30,
		})

		if err != nil {
			slog.Error("failed to send push", "user_id", userID.Hex(), "error", err)
			if resp != nil && resp.StatusCode == 410 {
				h.Repos.Subscriptions.Delete(ctx, userID)
			}
			return
		}

		if resp != nil {
			resp.Body.Close()
		}
	}()
}
