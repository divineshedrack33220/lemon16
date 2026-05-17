# InstaPing - Real-time Social Connection Platform

[![Go Version](https://img.shields.io/badge/Go-1.21+-00ADD8?style=flat&logo=go)](https://go.dev/)
[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?style=flat&logo=flutter)](https://flutter.dev/)
[![MongoDB](https://img.shields.io/badge/MongoDB-4.4+-47A248?style=flat&logo=mongodb)](https://www.mongodb.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Render](https://img.shields.io/badge/Deployed%20on-Render-46E3B7?style=flat&logo=render)](https://render.com)

InstaPing is a comprehensive full-stack social networking ecosystem that enables real-time communication, location-based user discovery, and interactive feed management. It features a robust Go backend, a modern PWA-ready web frontend, and a high-performance Flutter mobile application.

---

## ✨ Features

### 🔐 Core Ecosystem
- **Multi-Platform Support**: Seamless experience across Web and Mobile (Android/iOS).
- **Authentication System**: Secure Email/Password registration and Google OAuth 2.0 integration.
- **Real-time Messaging**: Instant communication powered by WebSocket with typing indicators and online status.
- **Location-based Discovery**: Find and connect with users nearby using geolocation services.
- **Social Feed**: Create posts, share updates, and interact with the community.
- **Push Notifications**: Stay updated with Web Push API and mobile notification support.
- **Media Management**: High-quality image sharing and profile customization via Cloudinary.

### 🛠️ Technical Highlights
- **RESTful API**: Scalable Gin-based backend with proper HTTP method implementation.
- **Live WebSocket Manager**: Efficient handling of real-time events and message broadcasting.
- **Optimized Database**: MongoDB indexing and schema design for high-performance queries.
- **Security First**: JWT authentication, bcrypt password hashing, CORS protection, and rate limiting.
- **Offline Capabilities**: Progressive Web App (PWA) support with service workers for the web frontend.

---

## 🛠️ Tech Stack

### Backend
- **Language**: Go 1.21+
- **Framework**: Gin Gonic
- **Real-time**: Gorilla WebSocket
- **Database**: MongoDB
- **Auth**: JWT (JSON Web Tokens)
- **Cloud Storage**: Cloudinary SDK
- **Notifications**: WebPush Library

### Mobile App
- **Framework**: Flutter (Dart)
- **State Management**: Shared Preferences & Provider patterns
- **Networking**: Http & WebSocket Channel
- **UI Components**: Shimmer effects, Cached Network Images
- **Features**: Geolocation, Image Picker, Share Plus

### Web Frontend
- **Languages**: HTML5, Vanilla JavaScript, CSS3
- **Design**: Responsive layout with modern aesthetics
- **PWA**: Service Workers & Manifest.json
- **APIs**: Geolocation API, WebSocket API, Web Push API

---

## 🚀 Quick Start

### Prerequisites
- [Go 1.21+](https://go.dev/dl/)
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [MongoDB](https://www.mongodb.com/try/download/community)
- Cloudinary Account (for image uploads)
- Google Cloud Console (for Google Auth)

### Installation

1. **Clone the Repository**
   ```bash
   git clone https://github.com/divineshedrack33220/lemon16.git
   cd lemon16
   ```

2. **Backend Setup**
   ```bash
   cd backend
   # Create a .env file based on the environment variables section below
   go mod download
   go run main.go
   ```

3. **Mobile App Setup**
   ```bash
   cd ../mobile_app
   flutter pub get
   flutter run
   ```

4. **Web Frontend**
   The frontend is served automatically by the backend at `http://localhost:8080` (or your configured `PORT`).

---

## ⚙️ Environment Variables

Create a `.env` file in the `backend/` directory:

```env
PORT=8080
MONGODB_URI=mongodb://localhost:27017/instaping
JWT_SECRET=your_super_secret_key
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret
```

---

## 📁 Project Structure

```text
lemon16/
├── backend/            # Go Gin Server
│   ├── database/       # MongoDB Connection & Logic
│   ├── handlers/       # API Request Handlers
│   ├── middleware/     # Auth & Security Middlewares
│   ├── models/         # Data Models (User, Post, Message)
│   ├── routes/         # API Route Definitions
│   ├── websocket/      # WebSocket Connection Manager
│   └── main.go         # Entry Point
├── frontend/           # Vanilla JS Web App (Served by Go)
│   ├── asset/          # Static Assets
│   ├── css/            # Stylesheets
│   ├── js/             # Frontend Logic
│   └── *.html          # UI Pages (index, chat, profile, etc.)
├── mobile_app/         # Flutter Application
│   ├── lib/            # Dart Source Code
│   │   ├── models/     # Data Classes
│   │   ├── screens/    # UI Screens
│   │   └── widgets/    # Reusable Components
│   └── pubspec.yaml    # Flutter Dependencies
└── render.yaml         # Deployment Configuration
```

---

## 🔌 API Endpoints (Quick Reference)

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/api/signup` | `POST` | Register a new user |
| `/api/login` | `POST` | Authenticate user & get JWT |
| `/api/me` | `GET/PUT` | Get or update current user profile |
| `/api/feed` | `GET` | Retrieve the global social feed |
| `/api/post` | `POST` | Create a new community post |
| `/api/chats` | `GET` | Get list of active conversations |
| `/api/messages/:id`| `GET` | Fetch message history for a chat |
| `/api/users/nearby`| `GET` | Discover users based on proximity |
| `/ws` | `WS` | WebSocket connection for real-time events |

---

## 👤 Author

**Divine Shedrack**
- GitHub: [@divineshedrack33220](https://github.com/divineshedrack33220)

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Built with ❤️ by Divine Shedrack
