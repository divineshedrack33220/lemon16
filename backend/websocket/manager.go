package websocket

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "sync"
    "time"

    "coded/middleware"

    "github.com/golang-jwt/jwt/v5"
    "github.com/gorilla/websocket"
)

type Manager struct {
    clients    map[*Client]bool
    broadcast  chan []byte
    register   chan *Client
    unregister chan *Client
    mu         sync.RWMutex
}

type Client struct {
    conn     *websocket.Conn
    userID   string
    send     chan []byte
    manager  *Manager
}

func NewManager() *Manager {
    return &Manager{
        clients:    make(map[*Client]bool),
        broadcast:  make(chan []byte),
        register:   make(chan *Client),
        unregister: make(chan *Client),
    }
}

func (m *Manager) Start() {
    for {
        select {
        case client := <-m.register:
            m.mu.Lock()
            m.clients[client] = true
            m.mu.Unlock()
            log.Printf("✅ WebSocket client registered. Total clients: %d", len(m.clients))
            
        case client := <-m.unregister:
            m.mu.Lock()
            if _, ok := m.clients[client]; ok {
                delete(m.clients, client)
                close(client.send)
            }
            m.mu.Unlock()
            log.Printf("❌ WebSocket client unregistered. Total clients: %d", len(m.clients))
            
        case message := <-m.broadcast:
            m.mu.RLock()
            // Create a slice of clients to avoid potential deadlocks or map modification issues
            clientsToBroadcast := make([]*Client, 0, len(m.clients))
            for client := range m.clients {
                clientsToBroadcast = append(clientsToBroadcast, client)
            }
            m.mu.RUnlock()

            for _, client := range clientsToBroadcast {
                select {
                case client.send <- message:
                default:
                    m.mu.Lock()
                    if _, ok := m.clients[client]; ok {
                        close(client.send)
                        delete(m.clients, client)
                    }
                    m.mu.Unlock()
                }
            }
        }
    }
}

func (m *Manager) BroadcastNewMessage(message map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "new_message",
        "payload": message,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    log.Printf("📢 Broadcasting new message to %d clients", len(m.clients))
    m.broadcast <- msg
}

func (m *Manager) BroadcastNewRequest(requestData map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "new_request",
        "payload": requestData,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket request: %v", err)
        return
    }
    
    log.Printf("📢 Broadcasting new request to %d clients", len(m.clients))
    m.broadcast <- msg
}

func (m *Manager) BroadcastRequestUpdate(updateData map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "request_update",
        "payload": updateData,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket request update: %v", err)
        return
    }
    
    m.broadcast <- msg
}

func (m *Manager) BroadcastChatCreated(chatData map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "chat_created",
        "payload": chatData,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    log.Printf("📢 Broadcasting chat created to %d clients", len(m.clients))
    m.broadcast <- msg
}

func (m *Manager) BroadcastMessageRead(payload map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "message_read",
        "payload": payload,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    m.broadcast <- msg
}

func (m *Manager) BroadcastTypingStart(payload map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "typing_start",
        "payload": payload,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    m.broadcast <- msg
}

func (m *Manager) BroadcastTypingEnd(payload map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "typing_end",
        "payload": payload,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    m.broadcast <- msg
}

func (m *Manager) BroadcastMessageReaction(payload map[string]interface{}) {
    data := map[string]interface{}{
        "type":    "message_reaction",
        "payload": payload,
    }
    
    msg, err := json.Marshal(data)
    if err != nil {
        log.Printf("❌ Error marshaling WebSocket message: %v", err)
        return
    }
    
    m.broadcast <- msg
}

func (m *Manager) GetConnectedUsers() int {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return len(m.clients)
}

var upgrader = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool {
        return true
    },
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
}

func WebSocketHandler(manager *Manager) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        tokenString := r.URL.Query().Get("token")
        if tokenString == "" {
            log.Printf("❌ WebSocket connection rejected: no token provided")
            http.Error(w, "Token required", http.StatusUnauthorized)
            return
        }
        
        // Validate JWT token
        claims := &middleware.Claims{}
        token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
            if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
                return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
            }
            
            jwtSecret := os.Getenv("JWT_SECRET")
            if jwtSecret == "" {
                jwtSecret = "your-secret-key-change-this-in-production"
            }
            return []byte(jwtSecret), nil
        })

        if err != nil || !token.Valid {
            log.Printf("❌ WebSocket connection rejected: invalid token: %v", err)
            http.Error(w, "Invalid token", http.StatusUnauthorized)
            return
        }

        userID := claims.UserID
        log.Printf("👤 WebSocket authenticated user: %s", userID)
        
        conn, err := upgrader.Upgrade(w, r, nil)
        if err != nil {
            log.Printf("❌ WebSocket upgrade failed: %v", err)
            return
        }
        
        client := &Client{
            conn:    conn,
            userID:  userID,
            send:    make(chan []byte, 256),
            manager: manager,
        }
        
        manager.register <- client
        
        // Send connection success message
        welcomeMsg := map[string]interface{}{
            "type": "connected",
            "payload": map[string]interface{}{
                "userId":  userID,
                "message": "WebSocket connected successfully",
                "time":    time.Now().Unix(),
            },
        }
        msg, _ := json.Marshal(welcomeMsg)
        client.send <- msg
        
        // Start goroutines for this client
        go client.writePump()
        go client.readPump()
    }
}

func (c *Client) readPump() {
    defer func() {
        c.manager.unregister <- c
        c.conn.Close()
    }()
    
    c.conn.SetReadLimit(512)
    c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
    c.conn.SetPongHandler(func(string) error {
        c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
        return nil
    })
    
    for {
        _, message, err := c.conn.ReadMessage()
        if err != nil {
            if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
                log.Printf("❌ WebSocket read error: %v", err)
            }
            break
        }
        
        var data map[string]interface{}
        if err := json.Unmarshal(message, &data); err != nil {
            log.Printf("❌ WebSocket message unmarshal error: %v", err)
            continue
        }
        
        log.Printf("📨 WebSocket message from user %s: %v", c.userID, data)
        
        // Handle different message types
        switch data["type"] {
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
    ticker := time.NewTicker(30 * time.Second)
    defer func() {
        ticker.Stop()
        c.conn.Close()
    }()
    
    for {
        select {
        case message, ok := <-c.send:
            c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
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
            c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
            if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
                return
            }
        }
    }
}

func (c *Client) handleSubscribe(data map[string]interface{}) {
    channel, ok := data["channel"].(string)
    if !ok {
        return
    }
    
    response := map[string]interface{}{
        "type": "subscribed",
        "payload": map[string]interface{}{
            "channel": channel,
            "userId":  c.userID,
            "time":    time.Now().Unix(),
        },
    }
    
    msg, err := json.Marshal(response)
    if err != nil {
        log.Printf("❌ Error marshaling subscription response: %v", err)
        return
    }
    
    c.send <- msg
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
    
    response := map[string]interface{}{
        "type": "chat_subscribed",
        "payload": map[string]interface{}{
            "chatId": chatID,
            "userId": c.userID,
        },
    }
    
    msg, err := json.Marshal(response)
    if err != nil {
        log.Printf("❌ Error marshaling chat subscription response: %v", err)
        return
    }
    
    c.send <- msg
}

func (c *Client) handleTypingStart(data map[string]interface{}) {
    // Broadcast typing start to other clients
    if payload, ok := data["payload"].(map[string]interface{}); ok {
        typingData := map[string]interface{}{
            "type": "typing_start",
            "payload": map[string]interface{}{
                "chatId":    payload["chatId"],
                "userId":    c.userID,
                "timestamp": time.Now().Unix(),
            },
        }
        
        msg, err := json.Marshal(typingData)
        if err != nil {
            log.Printf("❌ Error marshaling typing start: %v", err)
            return
        }
        
        c.manager.broadcast <- msg
    }
}

func (c *Client) handleTypingEnd(data map[string]interface{}) {
    // Broadcast typing end to other clients
    if payload, ok := data["payload"].(map[string]interface{}); ok {
        typingData := map[string]interface{}{
            "type": "typing_end",
            "payload": map[string]interface{}{
                "chatId":    payload["chatId"],
                "userId":    c.userID,
                "timestamp": time.Now().Unix(),
            },
        }
        
        msg, err := json.Marshal(typingData)
        if err != nil {
            log.Printf("❌ Error marshaling typing end: %v", err)
            return
        }
        
        c.manager.broadcast <- msg
    }
}

func (c *Client) handleMessageRead(data map[string]interface{}) {
    // Broadcast message read to other clients
    if payload, ok := data["payload"].(map[string]interface{}); ok {
        readData := map[string]interface{}{
            "type": "message_read",
            "payload": map[string]interface{}{
                "chatId":     payload["chatId"],
                "userId":     c.userID,
                "messageIds": payload["messageIds"],
                "timestamp":  time.Now().Unix(),
            },
        }
        
        msg, err := json.Marshal(readData)
        if err != nil {
            log.Printf("❌ Error marshaling message read: %v", err)
            return
        }
        
        c.manager.broadcast <- msg
    }
}

func (c *Client) sendPong() {
    response := map[string]interface{}{
        "type": "pong",
        "payload": map[string]interface{}{
            "time": time.Now().Unix(),
        },
    }
    
    msg, err := json.Marshal(response)
    if err != nil {
        log.Printf("❌ Error marshaling pong: %v", err)
        return
    }
    
    c.send <- msg
}