import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/app_logo.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadCurrentUserId();
    _setupWebSocket();
  }

  Future<void> _loadCurrentUserId() async {
    final token = await ApiService.getToken();
    if (token != null) {
      final parts = token.split('.');
      if (parts.length == 3) {
        try {
          final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          _currentUserId = payload['userId'] ?? payload['sub'] ?? payload['id'];
        } catch (e) {
          print('Error decoding token: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final position = await ApiService.getCurrentPosition();
      final lat = position?.latitude ?? 0;
      final lng = position?.longitude ?? 0;
      
      final users = await ApiService.getNearbyUsers(lat, lng);
      if (mounted) {
        setState(() {
          _users = users.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load users';
        });
      }
    }
  }

  String _formatDistance(dynamic d) {
    if (d == null) return 'Nearby';
    return d.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: const AppLogo(),
        title: const Text('Nearby Users', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: _loadUsers)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_error!, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _loadUsers, child: const Text('Retry')),
                ]))
              : _users.isEmpty
                  ? const Center(child: Text('No users nearby', style: TextStyle(fontSize: 18, color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final name = user['name']?.toString() ?? 'User';
                          final avatar = user['avatar']?.toString();
                          final distance = _formatDistance(user['distance']);
                          final userId = user['id']?.toString() ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundImage: avatar != null && avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                child: avatar == null || avatar.isEmpty ? Text(name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(distance),
                              trailing: IconButton(
                                icon: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF00AEEF), shape: BoxShape.circle), child: const Icon(Icons.chat_bubble_outline, color: Colors.black, size: 20)),
                                onPressed: () async {
                                  try {
                                    final result = await ApiService.createChat(userId);
                                    final chatId = result['id'] ?? result['_id'];
                                    if (chatId != null && mounted) {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)));
                                    }
                                  } catch (_) {}
                                },
                              ),
                              onTap: () {
                                if (userId.isNotEmpty) {
                                  Navigator.pushNamed(context, '/view-profile', arguments: {'userId': userId});
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
      bottomNavigationBar: const CustomBottomNavBar(currentRoute: '/nearby'),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF00AEEF),
      ),
    );
  }

  void _setupWebSocket() {
    _wsSubscription = WebSocketService.stream.listen((data) {
      _handleWebSocketMessage(data);
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    final type = data['type'];
    final payload = data['payload'];

    if (!mounted) return;

    switch (type) {
      case 'new_message':
        if (payload?['senderId'] != _currentUserId) {
          final senderName = payload?['senderName'] ?? 'Someone';
          _showToast('📩 New message from $senderName');
          NotificationService.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: senderName,
            body: payload?['content'] ?? 'Sent you a message',
          );
        }
        break;
      case 'post_accepted':
        if (payload?['userId'] != _currentUserId) {
          final userName = payload?['userName'] ?? 'Someone';
          _showToast('🤝 Request accepted by $userName');
          NotificationService.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: 'Request Accepted',
            body: '$userName accepted your request!',
          );
        }
        break;
      case 'post_favorited':
        if (payload?['userId'] != _currentUserId) {
          _showToast('⭐ Someone favorited your request');
          NotificationService.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: 'New Favorite',
            body: 'Someone favorited your request!',
          );
        }
        break;
    }
  }
}
