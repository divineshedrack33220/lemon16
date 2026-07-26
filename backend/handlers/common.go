package handlers

import (
	"coded/websocket"
)

var fallbackAvatar = "https://upload.wikimedia.org/wikipedia/commons/8/89/Portrait_Placeholder.png"

func SetWebSocketManager(manager *websocket.Manager) {
	// Kept for backward compatibility during transition
}
