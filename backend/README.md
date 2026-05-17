# InstaPing Backend - Go Gin API

The core engine of the InstaPing ecosystem, providing a high-performance RESTful API and WebSocket management for real-time social interactions.

## 🚀 Features

- **Gin Framework**: High-performance routing and middleware.
- **WebSocket Manager**: Custom manager for handling thousands of concurrent real-time connections.
- **JWT Auth**: Stateless authentication for Web and Mobile.
- **MongoDB**: Flexible and scalable data storage.
- **Cloudinary Integration**: Automated image processing and storage.
- **Web Push**: VAPID-based push notifications for browsers.

## 🛠️ Getting Started

### Prerequisites
- Go 1.21+
- MongoDB 4.4+
- `.env` file with required keys (see main README)

### Installation

1. **Install Dependencies**
   ```bash
   go mod download
   ```

2. **Run the Server**
   ```bash
   go run main.go
   ```

## 📁 Structure

- `handlers/`: Logic for API endpoints.
- `routes/`: Endpoint definitions and grouping.
- `websocket/`: Connection pooling and message broadcasting logic.
- `database/`: DB connection and collection helpers.
- `models/`: Go structs mapping to MongoDB documents.

## 🔗 Related
For the full system overview, see the [Root README](../README.md).
