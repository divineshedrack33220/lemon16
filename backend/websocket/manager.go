package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"coded/middleware"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

const (
	maxMessageSize = 4096
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	writeWait      = 10 * time.Second
	maxConnsPerUser = 5
)

type Manager struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	rooms      map[string]map[*Client]bool // roomID -> set of clients
	mu         sync.RWMutex
	ctx        context.Context
	cancel     context.CancelFunc
}

type Client struct {
	conn    *websocket.Conn
	userID  string
	send    chan []byte
	rooms   map[string]bool // rooms this client has joined
	manager *Manager
	mu      sync.Mutex
	closed  bool
}

func NewManager() *Manager {
	ctx, cancel := context.WithCancel(context.Background())
	return &Manager{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		rooms:      make(map[string]map[*Client]bool),
		ctx:        ctx,
		cancel:     cancel,
	}
}

func (m *Manager) Start() {
	for {
		select {
		case <-m.ctx.Done():
			return
		case client := <-m.register:
			m.mu.Lock()
			// Enforce per-user connection limit
			connCount := 0
			for c := range m.clients {
				if c.userID == client.userID {
					connCount++
				}
			}
			if connCount >= maxConnsPerUser {
				m.mu.Unlock()
				slog.Warn("connection rejected", "user_id", client.userID, "max_conns", maxConnsPerUser)
				client.safeClose()
				continue
			}
			m.clients[client] = true
			totalClients := len(m.clients)
			m.mu.Unlock()
			slog.Info("client registered", "user_id", client.userID, "total", totalClients)

		case client := <-m.unregister:
			m.mu.Lock()
			if _, ok := m.clients[client]; ok {
				// Remove from all rooms
				for roomID := range client.rooms {
					if roomClients, exists := m.rooms[roomID]; exists {
						delete(roomClients, client)
						if len(roomClients) == 0 {
							delete(m.rooms, roomID)
						}
					}
				}
				delete(m.clients, client)
				client.safeClose()
			}
			totalClients := len(m.clients)
			m.mu.Unlock()
			slog.Info("client unregistered", "user_id", client.userID, "total", totalClients)

		case message := <-m.broadcast:
			m.mu.RLock()
			clientsToBroadcast := make([]*Client, 0, len(m.clients))
			for client := range m.clients {
				clientsToBroadcast = append(clientsToBroadcast, client)
			}
			m.mu.RUnlock()

			for _, client := range clientsToBroadcast {
				select {
				case client.send <- message:
				default:
					// Client buffer full, disconnect it
					m.mu.Lock()
					if _, ok := m.clients[client]; ok {
						delete(m.clients, client)
						client.safeClose()
					}
					m.mu.Unlock()
				}
			}
		}
	}
}

// Shutdown gracefully stops the manager
func (m *Manager) Shutdown() {
	m.cancel()
	m.mu.Lock()
	for client := range m.clients {
		client.safeClose()
		delete(m.clients, client)
	}
	m.mu.Unlock()
}

// BroadcastToRoom sends a message only to clients in a specific room
func (m *Manager) BroadcastToRoom(roomID string, msg []byte, exclude *Client) {
	m.mu.RLock()
	roomClients, exists := m.rooms[roomID]
	if !exists {
		m.mu.RUnlock()
		return
	}
	clients := make([]*Client, 0, len(roomClients))
	for c := range roomClients {
		if c != exclude {
			clients = append(clients, c)
		}
	}
	m.mu.RUnlock()

	for _, client := range clients {
		select {
		case client.send <- msg:
		default:
			m.mu.Lock()
			if _, ok := m.clients[client]; ok {
				delete(m.clients, client)
				client.safeClose()
			}
			m.mu.Unlock()
		}
	}
}

// SendToUser sends a message to all connections of a specific user
func (m *Manager) SendToUser(userID string, msg []byte) {
	m.mu.RLock()
	var targets []*Client
	for client := range m.clients {
		if client.userID == userID {
			targets = append(targets, client)
		}
	}
	m.mu.RUnlock()

	for _, client := range targets {
		select {
		case client.send <- msg:
		default:
			m.mu.Lock()
			if _, ok := m.clients[client]; ok {
				delete(m.clients, client)
				client.safeClose()
			}
			m.mu.Unlock()
		}
	}
}

// safeClose prevents double-close panics
func (c *Client) safeClose() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.closed {
		c.closed = true
		close(c.send)
	}
}

// JoinRoom adds a client to a room
func (m *Manager) JoinRoom(client *Client, roomID string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.rooms[roomID] == nil {
		m.rooms[roomID] = make(map[*Client]bool)
	}
	m.rooms[roomID][client] = true
	client.mu.Lock()
	client.rooms[roomID] = true
	client.mu.Unlock()
}

// LeaveRoom removes a client from a room
func (m *Manager) LeaveRoom(client *Client, roomID string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if roomClients, exists := m.rooms[roomID]; exists {
		delete(roomClients, client)
		if len(roomClients) == 0 {
			delete(m.rooms, roomID)
		}
	}
	client.mu.Lock()
	delete(client.rooms, roomID)
	client.mu.Unlock()
}

func marshalAndLog(data map[string]interface{}, context string) []byte {
	msg, err := json.Marshal(data)
	if err != nil {
		slog.Error("error marshaling", "context", context, "error", err)
		return nil
	}
	return msg
}

func (m *Manager) BroadcastNewMessage(message map[string]interface{}, chatID string) {
	msg := marshalAndLog(map[string]interface{}{
		"type":    "new_message",
		"payload": message,
	}, "new_message")
	if msg == nil {
		return
	}

	if chatID != "" {
		m.BroadcastToRoom("chat:"+chatID, msg, nil)
	} else {
		m.broadcast <- msg
	}
}

func (m *Manager) BroadcastNewRequest(requestData map[string]interface{}) {
	msg := marshalAndLog(map[string]interface{}{
		"type":    "new_request",
		"payload": requestData,
	}, "new_request")
	if msg == nil {
		return
	}
	m.broadcast <- msg
}

func (m *Manager) BroadcastRequestUpdate(updateData map[string]interface{}) {
	msg := marshalAndLog(map[string]interface{}{
		"type":    "request_update",
		"payload": updateData,
	}, "request_update")
	if msg == nil {
		return
	}
	m.broadcast <- msg
}

func (m *Manager) BroadcastChatCreated(chatData map[string]interface{}) {
	msg := marshalAndLog(map[string]interface{}{
		"type":    "chat_created",
		"payload": chatData,
	}, "chat_created")
	if msg == nil {
		return
	}
	m.broadcast <- msg
}

func (m *Manager) BroadcastMessageRead(payload map[string]interface{}) {
	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type":    "message_read",
		"payload": payload,
	}, "message_read")
	if msg == nil {
		return
	}

	if chatID != "" {
		m.BroadcastToRoom("chat:"+chatID, msg, nil)
	} else {
		m.broadcast <- msg
	}
}

func (m *Manager) BroadcastTypingStart(payload map[string]interface{}) {
	chatID, _ := payload["chatId"].(string)
	userID, _ := payload["userId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type":    "typing_start",
		"payload": payload,
	}, "typing_start")
	if msg == nil {
		return
	}

	if chatID != "" {
		m.BroadcastToRoom("chat:"+chatID, msg, nil)
	} else {
		m.broadcast <- msg
	}
	_ = userID
}

func (m *Manager) BroadcastTypingEnd(payload map[string]interface{}) {
	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type":    "typing_end",
		"payload": payload,
	}, "typing_end")
	if msg == nil {
		return
	}

	if chatID != "" {
		m.BroadcastToRoom("chat:"+chatID, msg, nil)
	} else {
		m.broadcast <- msg
	}
}

func (m *Manager) BroadcastMessageReaction(payload map[string]interface{}) {
	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type":    "message_reaction",
		"payload": payload,
	}, "message_reaction")
	if msg == nil {
		return
	}

	if chatID != "" {
		m.BroadcastToRoom("chat:"+chatID, msg, nil)
	} else {
		m.broadcast <- msg
	}
}

func (m *Manager) GetConnectedUsers() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.clients)
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true // Allow non-browser clients
		}
		// Check against allowed origins
		allowedOrigins := []string{
			"http://localhost",
			"http://127.0.0.1",
			"https://coded-backend.onrender.com",
		}
		for _, allowed := range allowedOrigins {
			if origin == allowed || len(origin) > len(allowed) && origin[:len(allowed)] == allowed {
				return true
			}
		}
		return false
	},
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

func WebSocketHandler(manager *Manager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tokenString := r.URL.Query().Get("token")
		if tokenString == "" {
			slog.Warn("websocket connection rejected: no token")
			http.Error(w, "Token required", http.StatusUnauthorized)
			return
		}

		claims := &middleware.Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(middleware.GetJWTSecret()), nil
		})

		if err != nil || !token.Valid {
			slog.Warn("websocket connection rejected: invalid token")
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		userID := claims.UserID
		slog.Info("websocket authenticated", "user_id", userID)

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			slog.Error("websocket upgrade failed", "error", err)
			return
		}

		client := &Client{
			conn:    conn,
			userID:  userID,
			send:    make(chan []byte, 256),
			rooms:   make(map[string]bool),
			manager: manager,
		}

		manager.register <- client

		welcomeMsg := marshalAndLog(map[string]interface{}{
			"type": "connected",
			"payload": map[string]interface{}{
				"userId":  userID,
				"message": "WebSocket connected successfully",
				"time":    time.Now().Unix(),
			},
		}, "welcome")
		if welcomeMsg != nil {
			client.send <- welcomeMsg
		}

		go client.writePump()
		go client.readPump()
	}
}

func (c *Client) readPump() {
	defer func() {
		c.manager.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				slog.Warn("websocket read error", "user_id", c.userID, "error", err)
			}
			return
		}

		var data map[string]interface{}
		if err := json.Unmarshal(message, &data); err != nil {
			slog.Warn("websocket unmarshal error", "user_id", c.userID, "error", err)
			continue
		}

		switch data["type"] {
		case "join_room":
			c.handleJoinRoom(data)
		case "leave_room":
			c.handleLeaveRoom(data)
		case "subscribe":
			c.handleSubscribe(data)
		case "subscribe_chat":
			c.handleSubscribeChat(data)
		case "typing_start":
			c.handleTypingStart(data)
		case "typing_end":
			c.handleTypingEnd(data)
		case "message_read":
			c.handleMessageRead(data)
		case "ping":
			c.sendPong()
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) handleJoinRoom(data map[string]interface{}) {
	roomID, ok := data["roomId"].(string)
	if !ok || roomID == "" {
		return
	}
	c.manager.JoinRoom(c, roomID)
	slog.Info("user joined room", "user_id", c.userID, "room_id", roomID)
}

func (c *Client) handleLeaveRoom(data map[string]interface{}) {
	roomID, ok := data["roomId"].(string)
	if !ok || roomID == "" {
		return
	}
	c.manager.LeaveRoom(c, roomID)
	slog.Info("user left room", "user_id", c.userID, "room_id", roomID)
}

func (c *Client) handleSubscribe(data map[string]interface{}) {
	channel, ok := data["channel"].(string)
	if !ok {
		return
	}

	// Auto-join the channel as a room
	c.manager.JoinRoom(c, "channel:"+channel)

	msg := marshalAndLog(map[string]interface{}{
		"type": "subscribed",
		"payload": map[string]interface{}{
			"channel": channel,
			"userId":  c.userID,
			"time":    time.Now().Unix(),
		},
	}, "subscribed")
	if msg != nil {
		c.send <- msg
	}
}

func (c *Client) handleSubscribeChat(data map[string]interface{}) {
	payload, ok := data["payload"].(map[string]interface{})
	if !ok {
		return
	}

	chatID, ok := payload["chatId"].(string)
	if !ok {
		return
	}

	// Auto-join the chat room
	c.manager.JoinRoom(c, "chat:"+chatID)

	msg := marshalAndLog(map[string]interface{}{
		"type": "chat_subscribed",
		"payload": map[string]interface{}{
			"chatId": chatID,
			"userId": c.userID,
		},
	}, "chat_subscribed")
	if msg != nil {
		c.send <- msg
	}
}

func (c *Client) handleTypingStart(data map[string]interface{}) {
	payload, ok := data["payload"].(map[string]interface{})
	if !ok {
		return
	}

	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type": "typing_start",
		"payload": map[string]interface{}{
			"chatId":    chatID,
			"userId":    c.userID,
			"timestamp": time.Now().Unix(),
		},
	}, "typing_start")
	if msg == nil {
		return
	}

	if chatID != "" {
		c.manager.BroadcastToRoom("chat:"+chatID, msg, c)
	} else {
		c.manager.broadcast <- msg
	}
}

func (c *Client) handleTypingEnd(data map[string]interface{}) {
	payload, ok := data["payload"].(map[string]interface{})
	if !ok {
		return
	}

	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type": "typing_end",
		"payload": map[string]interface{}{
			"chatId":    chatID,
			"userId":    c.userID,
			"timestamp": time.Now().Unix(),
		},
	}, "typing_end")
	if msg == nil {
		return
	}

	if chatID != "" {
		c.manager.BroadcastToRoom("chat:"+chatID, msg, c)
	} else {
		c.manager.broadcast <- msg
	}
}

func (c *Client) handleMessageRead(data map[string]interface{}) {
	payload, ok := data["payload"].(map[string]interface{})
	if !ok {
		return
	}

	chatID, _ := payload["chatId"].(string)
	msg := marshalAndLog(map[string]interface{}{
		"type": "message_read",
		"payload": map[string]interface{}{
			"chatId":     chatID,
			"userId":     c.userID,
			"messageIds": payload["messageIds"],
			"timestamp":  time.Now().Unix(),
		},
	}, "message_read")
	if msg == nil {
		return
	}

	if chatID != "" {
		c.manager.BroadcastToRoom("chat:"+chatID, msg, c)
	} else {
		c.manager.broadcast <- msg
	}
}

func (c *Client) sendPong() {
	msg := marshalAndLog(map[string]interface{}{
		"type": "pong",
		"payload": map[string]interface{}{
			"time": time.Now().Unix(),
		},
	}, "pong")
	if msg != nil {
		c.send <- msg
	}
}
