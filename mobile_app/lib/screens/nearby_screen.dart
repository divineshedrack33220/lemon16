import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/app_logo.dart';
import '../widgets/loading_widget.dart';
import 'dart:async';
import '../main.dart';
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

  void _loadCurrentUserId() {
    _currentUserId = authService.userId ?? authService.decodeUserIdFromToken();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() { _isLoading = true; _error = null; });
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
          _error = 'Failed to load nearby users. Check your location permissions.';
        });
      }
    }
  }

  String _formatDistance(dynamic d) {
    if (d == null) return 'Nearby';
    final km = (d is num) ? d.toDouble() : double.tryParse(d.toString());
    if (km == null) return 'Nearby';
    if (km < 1) return '${(km * 1000).round()}m away';
    return '${km.toStringAsFixed(1)} km away';
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
          ? const AppLoadingShimmer(itemCount: 5, itemHeight: 72)
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _loadUsers)
              : _users.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.people_outline,
                      title: 'No one nearby yet',
                      subtitle: 'When people in your area start using Zukaping, they\'ll show up here. Try expanding your search radius or check back later.',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      color: kBrandColor,
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
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundImage: avatar != null && avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                backgroundColor: const Color(0xFF00AEEF).withValues(alpha: 0.15),
                                child: avatar == null || avatar.isEmpty
                                    ? Text(name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: kBrandColor))
                                    : null,
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(distance, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                              trailing: IconButton(
                                icon: Container(
                                  width: 40, height: 40,
                                  decoration: const BoxDecoration(color: kBrandColor, shape: BoxShape.circle),
                                  child: const Icon(Icons.chat_bubble_outline, color: Colors.black, size: 20),
                                ),
                                onPressed: () async {
                                  try {
                                    final result = await ApiService.createChat(userId);
                                    final chatId = result['id'] ?? result['_id'];
                                    if (chatId != null && mounted) {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)));
                                    }
                                  } catch (_) {
                                    if (mounted) showAppSnackBar(context, 'Failed to create chat', isError: true);
                                  }
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
        backgroundColor: kBrandColor,
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
