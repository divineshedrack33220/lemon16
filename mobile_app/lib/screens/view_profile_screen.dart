import "dart:convert";
import "package:http/http.dart" as http;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';

class ViewProfileScreen extends StatefulWidget {
  final String userId;

  const ViewProfileScreen({super.key, required this.userId});

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isFavorited = false;
  String? _error;
  int _currentPhotoIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadFavorites();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiService.getProfile(); // This gets current user
      // For viewing another user, you might need a different endpoint
      // Assuming you have a /api/user/:id endpoint
      final token = await ApiService.getToken();
      final http.Response res = await http.get(
        Uri.parse('${ApiService.baseUrl}/user/${widget.userId}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            _userData = data;
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        throw Exception('Failed to load profile');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'This profile is no longer available';
          _userData = {
            'name': 'Unknown User',
            'status': 'offline',
            'bio': 'This profile is no longer available or has been deleted.',
          };
        });
      }
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await ApiService.getFavorites();
      if (mounted) {
        setState(() {
          _isFavorited = favorites.any((f) => f['targetUserId'] == widget.userId);
        });
      }
    } catch (e) {
      print('Error loading favorites: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      await ApiService.toggleFavorite(widget.userId);
      if (mounted) {
        setState(() => _isFavorited = !_isFavorited);
        if (_isFavorited) {
          SoundService.playFavorite();
        }
        _showToast(_isFavorited ? 'Added to favorites' : 'Removed from favorites');
      }
    } catch (e) {
      _showToast('Failed to update favorite');
    }
  }

  Future<void> _startChat() async {
    if (_userData?['name'] == 'Unknown User') return;

    try {
      final result = await ApiService.createChat(widget.userId);
      final chatId = result['id'] ?? result['_id'];

      if (chatId != null) {
        _showToast('Chat created!');
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/chat',
            arguments: {'chatId': chatId},
          );
        }
      }
    } catch (e) {
      _showToast('Failed to create chat');
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

  void _openLightbox() {
    final photos = _getPhotos();
    if (photos.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PhotoLightbox(
          photos: photos,
          initialIndex: _currentPhotoIndex,
        ),
      ),
    );
  }

  List<String> _getPhotos() {
    if (_userData == null) return [];
    final photos = _userData!['photos'] as List<dynamic>?;
    if (photos != null && photos.isNotEmpty) {
      return photos.cast<String>();
    }
    final avatar = _userData!['avatar'] as String?;
    return avatar != null ? [avatar] : [];
  }

  String _formatDistance(dynamic distance) {
    if (distance == null) return '';
    if (distance is num) {
      return '${distance.toStringAsFixed(1)} km away';
    }
    return '$distance km away';
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final dateTime = timestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
        : DateTime.parse(timestamp.toString());
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    return '${diff.inHours} hours ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: null,
      ),
      body: _isLoading ? _buildShimmerLoading() : _buildContent(),
    );
  }

  Widget _buildShimmerLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Photo carousel shimmer
          Container(
            width: double.infinity,
            height: 380,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 44),
          // Name shimmer
          Container(
            width: 200,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),
          // Bio shimmer
          Container(
            width: 280,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 32),
          // Meta shimmer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 32),
              Container(
                width: 100,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // Rating shimmer
          Container(
            width: 120,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 40),
          // Chat button shimmer
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          const SizedBox(height: 24),
          // Secondary buttons shimmer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_userData == null) {
      return Center(
        child: Text(_error ?? 'Profile not available'),
      );
    }

    final photos = _getPhotos();
    final name = _userData!['name'] ?? 'Unknown User';
    final age = _userData!['age'];
    final bio = _userData!['bio'] ?? '';
    final status = _userData!['status'] ?? 'offline';
    final distance = _userData!['distance'];
    final rating = _userData!['rating'];
    final verified = _userData!['verified'] ?? false;
    final lastActive = _userData!['lastActive'];
    final interests = _userData!['interests'] as List<dynamic>?;
    final isUnknown = name == 'Unknown User';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Photo Carousel
          if (photos.isNotEmpty)
            GestureDetector(
              onTap: _openLightbox,
              child: Column(
                children: [
                  Container(
                    height: 380,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() => _currentPhotoIndex = index);
                        },
                        itemCount: photos.length,
                        itemBuilder: (context, index) {
                          return CachedNetworkImage(
                            imageUrl: photos[index],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[300],
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.person, size: 80, color: Colors.grey),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (photos.length > 1) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        photos.length,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == _currentPhotoIndex
                                ? const Color(0xFF00AEEF)
                                : Colors.grey[300],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              height: 380,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(Icons.person, size: 80, color: Colors.grey),
              ),
            ),

          const SizedBox(height: 32),

          // Name & Age
          Text(
            '$name${age != null ? ', $age' : ''}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              bio,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF666666),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),

          // Distance & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (distance != null)
                Text(
                  _formatDistance(distance),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF666666),
                  ),
                ),
              if (distance != null) const SizedBox(width: 16),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status == 'available'
                          ? const Color(0xFF00AEEF)
                          : status == 'busy'
                              ? Colors.yellow
                              : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status == 'available'
                        ? 'Available'
                        : status == 'busy'
                            ? 'Busy'
                            : 'Offline',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Rating
          if (rating != null) ...[
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Color(0xFFFFD700), size: 24),
                const SizedBox(width: 8),
                Text(
                  '$rating',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                  ),
                ),
                if (verified) ...[
                  const SizedBox(width: 8),
                  const Text(
                    '✓ Verified',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF00AEEF),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 32),

          // Action Buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isUnknown ? null : _startChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: isUnknown ? Colors.grey[200] : const Color(0xFF00AEEF),
                foregroundColor: isUnknown ? Colors.grey : Colors.black,
                disabledBackgroundColor: Colors.grey[200],
                disabledForegroundColor: Colors.grey,
              ),
              child: const Text(
                'Chat',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Secondary Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: isUnknown ? null : _toggleFavorite,
                icon: Icon(
                  _isFavorited ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorited ? Colors.red : const Color(0xFF8E8E8E),
                  size: 28,
                ),
                disabledColor: Colors.grey[400],
              ),
              const SizedBox(width: 32),
              IconButton(
                onPressed: isUnknown
                    ? null
                    : () => _showToast('Report action not implemented'),
                icon: const Icon(
                  Icons.report_gmailerrorred,
                  color: Color(0xFF8E8E8E),
                  size: 28,
                ),
                disabledColor: Colors.grey[400],
              ),
              const SizedBox(width: 32),
              IconButton(
                onPressed: isUnknown
                    ? null
                    : () => _showToast('Block action not implemented'),
                icon: const Icon(
                  Icons.block,
                  color: Color(0xFF8E8E8E),
                  size: 28,
                ),
                disabledColor: Colors.grey[400],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Additional Info
          if (lastActive != null || (interests != null && interests.isNotEmpty))
            Column(
              children: [
                if (lastActive != null)
                  Text(
                    'Last active ${_formatTime(lastActive)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (interests != null && interests.isNotEmpty)
                  Text(
                    'Mutual interests: ${interests.join(', ')}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// Fullscreen Lightbox for photos
class _PhotoLightbox extends StatelessWidget {
  final List<String> photos;
  final int initialIndex;

  const _PhotoLightbox({
    required this.photos,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: photos[index],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(Icons.broken_image, size: 80, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 40,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Icon(Icons.close, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}