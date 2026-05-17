import "chat_screen.dart";
import "dart:convert";
import "dart:async";
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/user.dart';
import '../widgets/app_logo.dart';
import '../services/sound_service.dart';
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _filteredFavorites = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _currentUserId;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  
  // Status management
  int _currentStatusIndex = 0;
  final List<Map<String, String>> _statuses = [
    {'text': 'Available', 'class': 'available', 'value': 'available'},
    {'text': 'Busy', 'class': 'busy', 'value': 'busy'},
    {'text': 'Offline', 'class': 'offline', 'value': 'offline'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _searchController.addListener(_filterFavorites);
    _scrollController.addListener(_onScroll);
    _setupWebSocket();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final token = await ApiService.getToken();
    if (token == null) {
      _navigateToLogin();
      return;
    }
    
    // Decode JWT to get userId (simplified)
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = _decodeBase64(parts[1]);
        _currentUserId = "";  // TODO: parse from token
      }
    } catch (e) {
      print('Error decoding token: $e');
    }
    
    await Future.wait([
      _loadFavorites(),
      _loadUserStatus(),
    ]);
  }

  String _decodeBase64(String str) {
    String normalized = base64.normalize(str);
    return utf8.decode(base64.decode(normalized));
  }

  Future<void> _loadFavorites({int attempt = 1}) async {
    try {
      final favorites = await ApiService.getFavorites();
      if (mounted) {
        setState(() {
          _favorites = favorites.cast<Map<String, dynamic>>();
          _filteredFavorites = List.from(_favorites);
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('Favorites load error: $e');
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: 2));
        _loadFavorites(attempt: attempt + 1);
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to load favorites. Please check your connection.';
          });
        }
      }
    }
  }

  Future<void> _loadUserStatus() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        final status = profile['status'] ?? 'available';
        final index = _statuses.indexWhere((s) => s['value'] == status);
        if (index != -1) {
          setState(() {
            _currentStatusIndex = index;
          });
        }
      }
    } catch (e) {
      print('Error loading status: $e');
    }
  }

  void _filterFavorites() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredFavorites = List.from(_favorites);
      } else {
        _filteredFavorites = _favorites.where((fav) {
          final user = fav['user'] ?? {};
          final name = (user['name'] ?? '').toLowerCase();
          final bio = (user['bio'] ?? '').toLowerCase();
          return name.contains(query) || bio.contains(query);
        }).toList();
      }
    });
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
          SoundService.playReceived();
          _showToast('📩 New message from ${payload?['senderName'] ?? 'Someone'}');
        }
        break;
      case 'post_accepted':
        if (payload?['userId'] != _currentUserId) {
          _showToast('🤝 Request accepted by ${payload?['userName'] ?? 'Someone'}');
        }
        break;
      case 'post_favorited':
        if (payload?['userId'] != _currentUserId) {
          _showToast('⭐ Someone favorited your request');
        }
        break;
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadFavorites();
    setState(() => _isRefreshing = false);
    _showToast('Favorites refreshed!');
  }

  void _onScroll() {
    // Pull to refresh can be handled with RefreshIndicator
  }

  Future<void> _removeFavorite(String userId, int index) async {
    try {
      // await ApiService.toggleFavorite(userId);
      _showToast('Removed from favorites 💔');
      
      setState(() {
        _favorites.removeAt(index);
        _filteredFavorites = List.from(_favorites);
      });
    } catch (e) {
      print('Remove favorite error: $e');
      _showToast('Failed to remove favorite');
    }
  }

  Future<void> _startChat(String userId) async {
    try {
      final result = await ApiService.createChat(userId);
      final chatId = result['id'] ?? result['_id'];
      if (chatId != null) {
        _showToast('Chat opened! 🚀');
        // Navigate to chat screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: chatId),
          ),
        );
      }
    } catch (e) {
      print('Start chat error: $e');
      _showToast('Failed to open chat');
    }
  }

  Future<void> _updateStatus() async {
    final newIndex = (_currentStatusIndex + 1) % _statuses.length;
    final newStatus = _statuses[newIndex]['value']!;
    
    // Optimistically update UI
    setState(() => _currentStatusIndex = newIndex);
    
    try {
      await ApiService.updateProfile({'status': newStatus});
      _showToast('Status changed to ${_statuses[newIndex]['text']}');
    } catch (e) {
      // Revert on failure
      setState(() {
        _currentStatusIndex = (_currentStatusIndex + 2) % _statuses.length;
      });
      _showToast('Failed to update status');
    }
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
          _buildStatusIndicator(),
        ],
        title: null,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentRoute: '/favorites',
        favoritesCount: _favorites.length,
      ),
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
        dotColor = const Color(0xFFFFFF00);
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '🔍 Search favorites by name...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildShimmerLoading();
    }
    
    if (_error != null) {
      return _buildErrorState();
    }
    
    if (_filteredFavorites.isEmpty) {
      return _buildEmptyState();
    }
    
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF00AEEF),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _filteredFavorites.length,
        itemBuilder: (context, index) {
          final fav = _filteredFavorites[index];
          final user = fav['user'] ?? {};
          return _buildFavoriteCard(user, fav['targetUserId'], index);
        },
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 200,
                        height: 15,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 120,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 32),
            Text(
              'Failed to load favorites',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadFavorites();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 120,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 32),
            Text(
              'No favorites yet',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You haven\'t saved anyone yet. Explore live requests and add people you like!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/feed');
              },
              child: const Text('Explore Live Requests →'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(Map<String, dynamic> user, String targetUserId, int index) {
    final name = user['name'] ?? 'User';
    final bio = user['bio'] ?? 'No bio yet';
    final avatar = user['avatar'];
    final distance = _formatDistance(user['distance']);
    final status = user['status'] ?? 'offline';
    
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
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _startChat(targetUserId),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _buildAvatar(avatar, name),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00AEEF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                distance,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF00AEEF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bio,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF666666),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              '⭐ Favorited',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF8E8E8E),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildStatusDot(status),
                            const SizedBox(width: 6),
                            Text(
                              status == 'available' ? 'Online' : status == 'busy' ? 'Busy' : 'Offline',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF8E8E8E),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _removeFavorite(targetUserId, index),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? avatarUrl, String name) {
    return Container(
      width: 72,
      height: 72,
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
        child: avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[300],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => _buildPlaceholderAvatar(name),
              )
            : _buildPlaceholderAvatar(name),
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
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot(String status) {
    Color dotColor;
    switch (status) {
      case 'available':
        dotColor = const Color(0xFF00AEEF);
        break;
      case 'busy':
        dotColor = const Color(0xFFFFFF00);
        break;
      default:
        dotColor = Colors.grey;
    }
    
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        boxShadow: status == 'available'
            ? [
                BoxShadow(
                  color: const Color(0xFF00AEEF).withOpacity(0.5),
                  blurRadius: 8,
                ),
              ]
            : status == 'busy'
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFFF00).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ]
                : null,
      ),
    );
  }
}