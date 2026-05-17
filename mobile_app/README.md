# 🚀 Zukaping Mobile

The mobile client for the **Zukaping ecosystem**, built with **Flutter**. This application provides a high-performance, cross-platform experience with real-time location features, dynamic chat, and instant social discovery.

## 🌟 Key Features

*   **📡 Radar Discovery**: Actively scan for and discover nearby users using real-time geolocation.
*   **💬 Live Chat**: Instant messaging powered by WebSockets, featuring typing indicators, read receipts, and reactions.
*   **📷 Media Sharing**: Capture or upload photos directly into chats with a smooth, optimized UI.
*   **📱 Glassmorphic UI**: Beautiful, modern interface with fluid animations and responsive design.
*   **🔐 Seamless Authentication**: Secure email/password and Google OAuth integration.
*   **✨ Profile Management**: Dynamic user profiles with customizable avatars, status indicators (e.g., "Available", "Ghost", "Super"), and multi-photo galleries.

## 🛠️ Technology Stack

*   **Framework**: [Flutter](https://flutter.dev/) (Dart)
*   **State Management**: `setState` with localized stream controllers for WebSockets.
*   **Networking**: `http` for REST APIs, `web_socket_channel` for real-time events.
*   **Location**: `geolocator` for GPS coordination.
*   **Media**: `image_picker` and `cached_network_image`.

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK (v3.19+)
*   Android Studio / Xcode
*   An active running instance of the **Zukaping Go Backend** (running on port `10000`).

### Installation

1.  **Clone & Install Dependencies**
    ```bash
    flutter pub get
    ```

2.  **Environment Setup**
    The app uses a platform-aware API service out-of-the-box.
    *   **Web (`localhost`)**: Auto-connects to `http://localhost:10000`
    *   **Android Emulator**: Auto-connects to `http://10.0.2.2:10000`
    
    *To override the API URL for physical devices or production, use:*
    ```bash
    flutter run --dart-define=API_URL=https://your-production-url.com/api
    ```

3.  **Run the App**
    ```bash
    flutter run -d chrome  # For Web testing
    # OR
    flutter run            # For Emulator/Device
    ```

## 📁 Project Structure

*   `/lib/models/`: Strongly typed Dart data models (e.g., `Message`, `User`, `Post`).
*   `/lib/screens/`: The core views (Feed, Chat, Profile, Onboarding).
*   `/lib/services/`: Core logic abstractions.
    *   `api_service.dart`: Centralized REST API client.
    *   `websocket_service.dart`: Singleton WebSocket manager.
*   `/lib/widgets/`: Reusable UI components (Bottom Nav, App Logo).

## 🤝 Contributing
Ensure you run `flutter analyze` and test both WebSocket and REST connectivity before committing major UI or state changes.

## 🔗 Related
For backend services, MongoDB schemas, and web frontend details, refer to the [Root Repository README](../README.md).
