import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/sound_service.dart';
import '../models/post.dart';
import '../widgets/app_logo.dart';
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  List<Post> _posts = [];
  List<Post> _nearbyUsers = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String? _currentUserId;
  
  // Status management
  int _currentStatusIndex = 0;
  final List<Map<String, String>> _statuses = [
    {'text': 'Available', 'class': 'available', 'value': 'available'},
    {'text': 'Busy', 'class': 'busy', 'value': 'busy'},
    {'text': 'Ghost', 'class': 'ghost', 'value': 'ghost'},
    {'text': 'Super', 'class': 'super', 'value': 'super'},
    {'text': 'Offline', 'class': 'offline', 'value': 'offline'},
  ];

  // Radar & Story Bar state
  bool _isRadarEnabled = false;

  // Broadcast scanning
  bool _isScanning = false;
  bool _showBroadcastOverlay = false;
  String _broadcastText = 'Broadcasting signal...';
  String _broadcastSubtext = 'Searching for users in your area';
  List<Post> _broadcastResults = [];
  Timer? _refreshTimer;
  Set<String> _favoriteUserIds = {};
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  Timer? _locationTimer;

  // Scroll management for "Viewing Vibes"
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
    _startAutoRefresh();
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _locationTimer?.cancel();
    _wsSubscription?.cancel();
    WebSocketService.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadFeed();
      if (true) {
        // WebSocketService.connect();
      }
    } else if (state == AppLifecycleState.paused) {
      WebSocketService.disconnect();
    }
  }

  Future<void> _initializeApp() async {
    final token = await ApiService.getToken();
    if (token == null) {
      _navigateToLogin();
      return;
    }

    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(
          utf8.decode(base64.decode(base64.normalize(parts[1])))
        );
        _currentUserId = payload['userId'] ?? payload['sub'] ?? payload['id'];
      }
    } catch (e) {
      print('Error decoding token: $e');
    }

    _setupWebSocket();
    
    _loadFeed();
    _loadUserStatus();
    _loadFavorites();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadFeed(),
    );
  }

  void _startLocationTracking() {
    // Check and update location every 10 minutes if user is 'available'
    _locationTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (_statuses[_currentStatusIndex]['value'] == 'available') {
        _updateCurrentLocation();
      }
    });
  }

  Future<void> _updateCurrentLocation() async {
    try {
      // Import geolocator if not present
      final position = await ApiService.getCurrentPosition(); // We'll add this helper
      if (position != null) {
        await ApiService.updateProfile({
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
        print('📍 Location auto-updated');
        _loadFeed(); // Refresh to see new nearby people
      }
    } catch (e) {
      print('Failed to auto-update location: $e');
    }
  }

  void _setupWebSocket() {
    // WebSocketService.connect();
    
    _wsSubscription = WebSocketService.stream.listen((data) {
      final type = data['type'] as String?;
      final payload = data['payload'] as Map<String, dynamic>?;

      switch (type) {
        case 'new_request':
          _handleNewRequest(payload);
          break;
        case 'request_update':
          _handleRequestUpdate(payload);
          break;
        case 'request_removed':
          _handleRequestRemoved(payload);
          break;
        case 'user_status_update':
          _handleUserStatusUpdate(payload);
          break;
        case 'nearby_users':
          _handleNearbyUsers(payload);
          break;
        case 'post_ignored':
          _handlePostIgnored(payload);
          break;
        case 'post_favorited':
          _handlePostFavorited(payload);
          break;
        case 'post_accepted':
          _handlePostAccepted(payload);
          break;
      }
    });
  }

  void _handleNewRequest(Map<String, dynamic>? request) {
    if (request == null) return;
    if (request['userId'] == _currentUserId) return;

    final post = Post.fromJson(request as Map<String, dynamic>);
    
    if (mounted) {
      setState(() {
        _posts.insert(0, post);
      });
      _showToast('📢 New request from ${post.userName}');
    }
  }

  void _handleRequestUpdate(Map<String, dynamic>? update) {
    if (update == null) return;
    
    final postId = update['id'];
    final index = _posts.indexWhere((p) => p.id == postId);
    
    if (index != -1 && mounted) {
      setState(() {
        _posts[index] = Post.fromJson(update);
      });
    }
  }

  void _handleRequestRemoved(Map<String, dynamic>? data) {
    if (data == null) return;
    
    final requestId = data['requestId'] ?? data['id'];
    if (mounted) {
      setState(() {
        _posts.removeWhere((p) => p.id == requestId);
      });
    }
  }

  void _handleUserStatusUpdate(Map<String, dynamic>? update) {
    if (update == null) return;
    
    final userId = update['userId'];
    final status = update['status'];
    
    // Update in feed
    if (mounted) {
      setState(() {
        _posts = _posts.map((post) {
          if (post.userId == userId) {
            // Could add status field to Post model
          }
          return post;
        }).toList();
      });
    }
  }

  void _handleNearbyUsers(Map<String, dynamic>? data) {
    if (data == null || !_isScanning) return;
    
    final users = data['users'] as List<dynamic>?;
    if (users != null && mounted) {
      setState(() {
        _nearbyUsers = users
            .where((u) => u != null)
            .map((u) => Post.fromJson(u as Map<String, dynamic>))
            .toList();
        
        if (_nearbyUsers.isNotEmpty) {
          _broadcastText = '${_nearbyUsers.length} user${_nearbyUsers.length > 1 ? 's' : ''} found nearby';
          _broadcastSubtext = 'Scroll to browse';
        } else {
          _broadcastText = 'No signals detected';
          _broadcastSubtext = 'No users found in your immediate area';
        }
      });
    }
  }

  void _handlePostIgnored(Map<String, dynamic>? payload) {
    if (payload == null) return;
    
    if (payload['userId'] != _currentUserId && payload['postId'] != null) {
      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p.id == payload['postId']);
        });
      }
    }
  }

  void _handlePostFavorited(Map<String, dynamic>? payload) {
    if (payload == null) return;
    // UI update if needed
  }

  void _handlePostAccepted(Map<String, dynamic>? payload) {
    if (payload == null) return;
    
    if (payload['userId'] != _currentUserId) {
      _showToast('🤝 ${payload['userName'] ?? 'Someone'} accepted a request');
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await ApiService.getFavorites();
      if (mounted) {
        setState(() {
          _favoriteUserIds = favorites
              .map((f) => f['targetUserId'] as String)
              .toSet();
        });
      }
    } catch (e) {
      print('Error loading favorites: $e');
    }
  }

  Future<void> _loadFeed() async {
    print("📡 Loading feed...");
    try {
      final posts = await ApiService.getFeed();
      if (mounted) {
        setState(() {
          _posts = posts
              .where((p) => p != null)
              .map((p) => Post.fromJson(p as Map<String, dynamic>))
              .toList();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load live requests';
        });
      }
    }
    _loadNearbyUsers();
  }

  Future<void> _loadNearbyUsers() async {
    try {
      final position = await ApiService.getCurrentPosition();
      final lat = position?.latitude ?? 0.0;
      final lng = position?.longitude ?? 0.0;
      
      final users = await ApiService.getNearbyUsers(lat, lng);
      if (mounted) {
        setState(() {
          _nearbyUsers = users
              .where((u) => u != null)
              .map((u) => Post.fromJson(u as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      print('Error auto-loading nearby users: $e');
    }
  }

  Future<void> _loadUserStatus() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        final status = profile['status'] ?? 'available';
        final index = _statuses.indexWhere((s) => s['value'] == status);
        if (index != -1) {
          setState(() => _currentStatusIndex = index);
        }
      }
    } catch (e) {
      print('Error loading status: $e');
    }
  }

  Future<void> _updateStatus() async {
    final newIndex = (_currentStatusIndex + 1) % _statuses.length;
    final newStatus = _statuses[newIndex]['value']!;
    
    setState(() => _currentStatusIndex = newIndex);
    
    try {
      await ApiService.updateProfile({'status': newStatus});
      _showToast('Status changed to ${_statuses[newIndex]['text']}');
      
      WebSocketService.send({
        'type': 'status_update',
        'status': newStatus,
        'userId': _currentUserId,
      });
    } catch (e) {
      setState(() {
        _currentStatusIndex = (_currentStatusIndex + 2) % _statuses.length;
      });
      _showToast('Failed to update status');
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadFeed();
    setState(() => _isRefreshing = false);
    _showToast('🔄 Feed refreshed');
  }

  Future<void> _broadcastScan() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _showBroadcastOverlay = true;
      _broadcastText = 'Broadcasting signal...';
      _broadcastSubtext = 'Searching for users in your area';
      _broadcastResults = [];
    });

    try {
      // Get actual position
      final position = await ApiService.getCurrentPosition();
      final lat = position?.latitude ?? 0;
      final lng = position?.longitude ?? 0;

      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 700));
        
        try {
          final users = await ApiService.getNearbyUsers(lat, lng);
          
          if (users.isNotEmpty && mounted) {
            setState(() {
              _nearbyUsers = users.map((u) => Post.fromJson(u)).toList();
              
              if (i == 2) {
                _broadcastText = '${_nearbyUsers.length} user${_nearbyUsers.length > 1 ? 's' : ''} found nearby';
                _broadcastSubtext = 'Scroll to browse';
                _broadcastResults = _nearbyUsers;
              }
            });
          } else if (i == 2 && mounted) {
            setState(() {
              _broadcastText = 'No signals detected';
              _broadcastSubtext = 'No users found in your immediate area';
            });
          }
        } catch (e) {
          print('Scan attempt $i failed: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _broadcastText = 'Broadcast failed';
          _broadcastSubtext = 'Signal transmission interrupted';
        });
        _showToast('Failed to scan nearby users');
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _handleAccept(Post post) async {
    try {
      final result = await ApiService.createChat(post.userId);
      final chatId = result['id'] ?? result['_id'];
      
      if (chatId != null) {
        _showToast('🤝 Chat created!');
        
        WebSocketService.send({
          'type': 'post_accepted',
          'postId': post.id,
          'userId': _currentUserId,
          'targetUserId': post.userId,
          'chatId': chatId,
        });
        
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });
        
        Navigator.pushNamed(context, '/chat', arguments: {'chatId': chatId});
      }
    } catch (e) {
      _showToast('Failed to create chat');
    }
  }

  Future<void> _handleFavorite(Post post, int index) async {
    try {
      await ApiService.toggleFavorite(post.userId);
      
      if (_favoriteUserIds.contains(post.userId)) {
        _favoriteUserIds.remove(post.userId);
        _showToast('💔 Removed from favorites');
      } else {
        _favoriteUserIds.add(post.userId);
        SoundService.playFavorite();
        _showToast('❤️ Added to favorites');
      }
      
      setState(() {
        _posts.removeAt(index);
      });
      
      WebSocketService.send({
        'type': 'post_favorited',
        'postId': post.id,
        'userId': _currentUserId,
        'targetUserId': post.userId,
      });
    } catch (e) {
      _showToast('Failed to update favorite');
    }
  }

  void _handleIgnore(Post post, int index) {
    setState(() {
      _posts.removeAt(index);
    });
    
    _showToast('👎 Request ignored');
    
    WebSocketService.send({
      'type': 'post_ignored',
      'postId': post.id,
      'userId': _currentUserId,
      'targetUserId': post.userId,
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  String _formatDistance(dynamic distance) {
    if (distance == null) return 'Nearby';
    
    double numDistance;
    if (distance is num) {
      numDistance = distance.toDouble();
    } else if (distance is String) {
      numDistance = double.tryParse(distance) ?? 0;
    } else {
      return 'Nearby';
    }
    
    if (numDistance < 1000) {
      return '${numDistance.round()}m away';
    } else {
      return '${(numDistance / 1000).toStringAsFixed(1)}km away';
    }
  }

  String _formatTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildStoryPlaceholder(String name) {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.1),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00AEEF),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _buildLogo(),
        actions: [
          IconButton(
            icon: Icon(
              _isRadarEnabled ? Icons.radar : Icons.radar_outlined,
              color: _isRadarEnabled ? const Color(0xFF00AEEF) : Colors.grey,
            ),
            onPressed: () {
              setState(() => _isRadarEnabled = !_isRadarEnabled);
              if (_isRadarEnabled) {
                _broadcastScan();
              } else {
                setState(() {
                  _showBroadcastOverlay = false;
                  _isScanning = false;
                });
              }
              _showToast(_isRadarEnabled ? 'Radar Activated 📡' : 'Radar Deactivated');
            },
          ),
          _buildStatusIndicator(),
        ],
        title: null,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildStoryBar(),
              Expanded(child: _buildBody()),
            ],
          ),
          _buildLocationFab(),
          if (_showBroadcastOverlay) _buildBroadcastOverlay(),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavBar(currentRoute: '/feed'),
    );
  }

  Widget _buildLogo() {
    return const AppLogo();
  }

  Widget _buildStatusIndicator() {
    final status = _statuses[_currentStatusIndex];
    Color dotColor;
    switch (status['class']) {
      case 'available':
        dotColor = const Color(0xFF00AEEF);
        break;
      case 'busy':
        dotColor = Colors.yellow;
        break;
      case 'ghost':
        dotColor = Colors.grey.withOpacity(0.5);
        break;
      case 'super':
        dotColor = Colors.deepPurpleAccent;
        break;
      default:
        dotColor = Colors.grey;
    }
    
    return GestureDetector(
      onTap: _updateStatus,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status['text']!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryBar() {
    // Show nearby users (excluding self) to keep it rich and colorful
    final displayUsers = _nearbyUsers
        .where((u) => u.userId != _currentUserId)
        .take(15)
        .toList();

    if (displayUsers.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: displayUsers.length,
        itemBuilder: (context, index) {
          final user = displayUsers[index];
          
          // Dynamic status colors for active premium border ring
          Color startColor;
          Color endColor;
          IconData statusIcon;
          Color statusIconColor;
          
          switch (user.userStatus) {
            case 'available':
              startColor = const Color(0xFF00AEEF);
              endColor = Colors.blue[200]!;
              statusIcon = Icons.flash_on;
              statusIconColor = const Color(0xFF00AEEF);
              break;
            case 'busy':
              startColor = Colors.amber;
              endColor = Colors.yellow[300]!;
              statusIcon = Icons.remove_circle;
              statusIconColor = Colors.amber;
              break;
            case 'ghost':
              startColor = Colors.grey[400]!;
              endColor = Colors.grey[200]!;
              statusIcon = Icons.visibility_off;
              statusIconColor = Colors.grey;
              break;
            case 'super':
              startColor = Colors.purpleAccent;
              endColor = Colors.deepPurple[200]!;
              statusIcon = Icons.star;
              statusIconColor = Colors.purple;
              break;
            default:
              startColor = const Color(0xFF00AEEF);
              endColor = Colors.blue[200]!;
              statusIcon = Icons.flash_on;
              statusIconColor = const Color(0xFF00AEEF);
          }

          return GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/view-profile', arguments: {'userId': user.userId});
            },
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [startColor, endColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: ClipOval(
                            child: (user.userAvatar != null && user.userAvatar!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: user.userAvatar!,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => _buildStoryPlaceholder(user.userName),
                                  )
                                : (user.userPhotos.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: user.userPhotos.first,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => _buildStoryPlaceholder(user.userName),
                                      )
                                    : _buildStoryPlaceholder(user.userName),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(statusIcon, size: 12, color: statusIconColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.userName.split(' ')[0],
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatDistance(user.distance),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _scrollToPost(String postId) {
    final key = _postKeys[postId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(seconds: 1),
        curve: Curves.easeInOut,
      );
    } else {
      _showToast('Could not find post location');
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildShimmerLoading();
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFeed,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_off, size: 96, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                'No live requests right now',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Be the first to post a request or check back soon — people are always looking to connect nearby.',
                style: TextStyle(fontSize: 16, color: Colors.grey[500], height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF00AEEF),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          // Ensure every post has a unique key for scrolling
          _postKeys[post.id] ??= GlobalKey();
          return Container(
            key: _postKeys[post.id],
            child: _buildPostCard(post, index),
          );
        },
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Column(
      children: [
        // Story Bar Shimmer
        Shimmer.fromColors(
          baseColor: Colors.grey[200]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            height: 130,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              itemBuilder: (_, __) => Container(
                width: 80,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    Container(width: 66, height: 66, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(height: 8),
                    Container(width: 40, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Posts Shimmer
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: Colors.grey[200]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[100]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 64, height: 64, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 120, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(height: 8),
                              Container(width: 60, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 8),
                      Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 8),
                      Container(width: 150, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        height: 180,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPostCard(Post post, int index) {
    final isFavorited = _favoriteUserIds.contains(post.userId);
    
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: post.userStatus == 'super' ? const Color(0xFFF0F7FF) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: post.userStatus == 'super' ? const Color(0xFF00AEEF).withOpacity(0.3) : Colors.grey[200]!,
            width: post.userStatus == 'super' ? 2 : 1,
          ),
          boxShadow: [
            if (post.userStatus == 'super')
              BoxShadow(
                color: const Color(0xFF00AEEF).withOpacity(0.1),
                blurRadius: 15,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              // View profile
              Navigator.pushNamed(context, '/view-profile', arguments: {'userId': post.userId});
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _PulseAvatar(
                            imageUrl: post.userAvatar,
                            userPhotos: post.userPhotos,
                            userName: post.userName,
                            isSuper: post.userStatus == 'super',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.userName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDistance(post.distance),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF666666),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '🔵 Live now',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF00AEEF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  // Category
                  if (post.category != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        post.category!,
                        style: const TextStyle(fontSize: 14, color: Colors.black),
                      ),
                    ),
                  ],
                  
                  // Content
                  const SizedBox(height: 12),
                  Text(
                    post.content,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF333333),
                      height: 1.4,
                    ),
                  ),
                  
                  // Footer
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Color(0xFFFFD700)),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(post.createdAt),
                            style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildActionButton(
                            Icons.close,
                            'Ignore',
                            () => _handleIgnore(post, index),
                          ),
                          const SizedBox(width: 8),
                          _buildActionButton(
                            Icons.favorite,
                            isFavorited ? 'Remove from favorites' : 'Add to favorites',
                            () => _handleFavorite(post, index),
                            color: isFavorited ? Colors.red : null,
                          ),
                          const SizedBox(width: 8),
                          _buildActionButton(
                            Icons.check,
                            'Accept request',
                            () => _handleAccept(post),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Icon(
          icon,
          color: color ?? const Color(0xFF333333),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildPlaceholderAvatar(String name) {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.2),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationFab() {
    return Positioned(
      bottom: 90,
      right: 20,
      child: GestureDetector(
        onTap: _broadcastScan,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF00AEEF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00AEEF).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(Icons.location_on, color: Colors.black, size: 28),
              ),
              if (_nearbyUsers.isNotEmpty)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                      child: Text(
                        '${_nearbyUsers.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withOpacity(0.98),
        child: Stack(
          children: [
            // Close button
            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showBroadcastOverlay = false;
                    _broadcastResults = [];
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Icon(Icons.close, color: Color(0xFF333333)),
                ),
              ),
            ),
            
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Radar animation
                  if (_broadcastResults.isEmpty)
                    SizedBox(
                      width: 300,
                      height: 300,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RadarAnimation(isScanning: _isScanning),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00AEEF),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00AEEF).withOpacity(0.8),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.location_on, size: 18, color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 40),
                  
                  Text(
                    _broadcastText,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _broadcastSubtext,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Results
                  if (_broadcastResults.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _broadcastResults.length,
                        itemBuilder: (context, index) {
                          final user = _broadcastResults[index];
                          return _buildBroadcastResultItem(user);
                        },
                      ),
                    ),
                  
                  if (_broadcastResults.isEmpty && !_isScanning)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No users nearby',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try moving to a different location or check back later',
                            style: TextStyle(color: Colors.grey[500]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBroadcastResultItem(Post user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: (user.userAvatar != null && user.userAvatar!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: user.userAvatar!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _buildPlaceholderAvatar(user.userName),
                    )
                  : (user.userPhotos.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: user.userPhotos.first,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => _buildPlaceholderAvatar(user.userName),
                        )
                      : _buildPlaceholderAvatar(user.userName),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.userName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDistance(user.distance),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  try {
                    final result = await ApiService.createChat(user.userId);
                    final chatId = result['id'] ?? result['_id'];
                    if (chatId != null) {
                      setState(() => _showBroadcastOverlay = false);
                      Navigator.pushNamed(context, '/chat', arguments: {'chatId': chatId});
                    }
                  } catch (e) {
                    _showToast('Failed to create chat');
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF333333)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/view-profile', arguments: {'userId': user.userId});
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.visibility, size: 18, color: Color(0xFF333333)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RadarAnimation extends StatefulWidget {
  final bool isScanning;
  const RadarAnimation({super.key, required this.isScanning});

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RadarAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !oldWidget.isScanning) {
      _controller.repeat();
    } else if (!widget.isScanning && oldWidget.isScanning) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(300, 300),
          painter: _AnimatedRadarPainter(
            animationValue: _controller.value,
            isScanning: widget.isScanning,
          ),
        );
      },
    );
  }
}

class _AnimatedRadarPainter extends CustomPainter {
  final double animationValue;
  final bool isScanning;
  
  _AnimatedRadarPainter({required this.animationValue, required this.isScanning});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    
    // Static Crosshairs
    final linePaint = Paint()
      ..color = const Color(0xFF00AEEF).withOpacity(0.2)
      ..strokeWidth = 1;
      
    // 4 lines
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), linePaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), linePaint);
    canvas.drawLine(Offset(center.dx - maxRadius * 0.7, center.dy - maxRadius * 0.7), Offset(center.dx + maxRadius * 0.7, center.dy + maxRadius * 0.7), linePaint);
    canvas.drawLine(Offset(center.dx - maxRadius * 0.7, center.dy + maxRadius * 0.7), Offset(center.dx + maxRadius * 0.7, center.dy - maxRadius * 0.7), linePaint);
    
    if (!isScanning) return;
    
    // Draw 3 expanding waves
    for (int i = 0; i < 3; i++) {
      double offset = (animationValue + (i * 0.33)) % 1.0;
      double radius = maxRadius * offset;
      double opacity = 1.0 - offset;
      
      final wavePaint = Paint()
        ..color = const Color(0xFF00AEEF).withOpacity(opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      if (radius > 0) {
        canvas.drawCircle(center, radius, wavePaint);
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant _AnimatedRadarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.isScanning != isScanning;
  }
}

class _PulseAvatar extends StatefulWidget {
  final String? imageUrl;
  final List<String> userPhotos;
  final String userName;
  final bool isSuper;

  const _PulseAvatar({
    this.imageUrl,
    this.userPhotos = const [],
    required this.userName,
    this.isSuper = false,
  });

  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulseColor = widget.isSuper ? Colors.deepPurpleAccent : const Color(0xFF00AEEF);
    final effectiveImageUrl = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
        ? widget.imageUrl
        : (widget.userPhotos.isNotEmpty ? widget.userPhotos.first : null);
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: pulseColor.withOpacity(1.0 - _controller.value),
                blurRadius: _controller.value * (widget.isSuper ? 15 : 10),
                spreadRadius: _controller.value * (widget.isSuper ? 8 : 5),
              ),
            ],
          ),
          child: effectiveImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: effectiveImageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey[300]),
                  errorWidget: (context, url, error) => _buildPlaceholderAvatar(widget.userName),
                )
              : _buildPlaceholderAvatar(widget.userName),
        );
      },
    );
  }

  Widget _buildPlaceholderAvatar(String name) {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.2),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
      ),
    );
  }
}