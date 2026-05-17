import "dart:convert";
import "package:http/http.dart" as http;
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/app_logo.dart';
import '../services/websocket_service.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  bool _isLoading = true;
  String? _error;
  String? _referralCode;
  String? _referralUrl;
  final ImagePicker _picker = ImagePicker();
  int _currentFullscreenIndex = 0;
  final PageController _fullscreenController = PageController();
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadReferralLink();
    _setupWebSocket();
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    final token = await ApiService.getToken();
    if (token != null) {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        _currentUserId = payload['id'];
      }
    }
  }

  @override
  void dispose() {
    _fullscreenController.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final data = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _user = User.fromJson(data);
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load profile';
        });
      }
    }
  }

  Future<void> _loadReferralLink() async {
    try {
      // This endpoint might need to be added to your backend
      final token = await ApiService.getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/me/referral'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _referralCode = data['referralCode'];
            _referralUrl = data['referralUrl'];
          });
        }
      }
    } catch (e) {
      print('Error loading referral: $e');
    }
  }

  Future<void> _changeAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null) {
      try {
        final bytes = await image.readAsBytes();
        final url = await ApiService.uploadImage(bytes, image.name);
        if (url != null && mounted) {
          await ApiService.updateProfile({'avatar': url});
          _showToast('Profile photo updated!');
          _loadProfile();
        }
      } catch (e) {
        _showToast('Failed to update photo');
      }
    }
  }

  Future<void> _shareProfile() async {
    if (_user == null) {
      _showToast('Profile not loaded yet');
      return;
    }

    final handle = _user!.name.toLowerCase().replaceAll(' ', '');
    final shareUrl = 'https://zukaping.app/@$handle';
    
    try {
      await Share.share(
        'Check out my profile on Zukaping!\nLet\'s connect: $shareUrl',
        subject: '${_user!.name}\'s Profile on Zukaping',
      );
    } catch (e) {
      _showToast('Failed to share profile');
    }
  }

  Future<void> _shareReferral() async {
    if (_referralUrl == null) {
      _showToast('Referral link not available');
      return;
    }

    try {
      await Share.share(
        '🎁 Join me on Zukaping!\nUse my referral link to unlock premium perks instantly:\n$_referralUrl',
        subject: 'You\'re invited to Zukaping!',
      );
    } catch (e) {
      _showToast('Failed to share');
    }
  }

  Future<void> _copyReferralLink() async {
    if (_referralUrl == null) {
      _showToast('Referral link not available');
      return;
    }

    await Clipboard.setData(ClipboardData(text: _referralUrl!));
    _showToast('Referral link copied!');
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (mounted) {
      _showToast('Logged out');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _openFullscreen(int index) {
    _currentFullscreenIndex = index;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullscreenViewer(
          photos: _user?.photos ?? [],
          initialIndex: index,
        ),
      ),
    );
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SettingsModal(
        referralCode: _referralCode,
        referralUrl: _referralUrl,
        onReferFriend: () {
          Navigator.pop(context);
          _showReferralModal();
        },
        onLogout: () {
          Navigator.pop(context);
          _showLogoutConfirmation();
        },
        onDeleteAccount: () {
          Navigator.pop(context);
          _confirmDeleteAccount();
        },
      ),
    );
  }

  void _showReferralModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ReferralModal(
        referralCode: _referralCode,
        referralUrl: _referralUrl,
        onCopyLink: _copyReferralLink,
        onShare: _shareReferral,
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/feed'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Account'),
        content: const Text(
            'This will permanently delete your account and all associated data. '
            'Are you sure you want to continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await ApiService.deleteAccount();
    if (result['message'] != null) {
      _showToast('Account deleted');
      // Clear bottom-nav cache
      CustomBottomNavBar.clearCache();
      // Navigate to login
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _showToast('Failed to delete account');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: const AppLogo(),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: _showSettingsModal,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmerLoading()
          : _error != null
              ? _buildErrorState()
              : _buildProfileContent(),
      bottomNavigationBar: const CustomBottomNavBar(currentRoute: '/profile'),
    );
  }

  Widget _buildShimmerLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar shimmer
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Name shimmer
          Center(
            child: Container(
              width: 180,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Handle shimmer
          Center(
            child: Container(
              width: 120,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Bio shimmer
          Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 32),
          // Buttons shimmer
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Grid shimmer
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProfile,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_user == null) return const SizedBox();

    final photos = _user!.photos;
    final effectiveAvatar = (_user!.avatar != null && _user!.avatar!.isNotEmpty)
        ? _user!.avatar
        : (_user!.photos.isNotEmpty ? _user!.photos.first : null);

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: const Color(0xFF00AEEF),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar
            GestureDetector(
              onTap: _changeAvatar,
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00AEEF),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00AEEF).withOpacity(0.1),
                          blurRadius: 0,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: effectiveAvatar != null
                          ? CachedNetworkImage(
                              imageUrl: effectiveAvatar,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                              ),
                              errorWidget: (context, url, error) => _buildPlaceholderAvatar(),
                            )
                          : _buildPlaceholderAvatar(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Username
            Text(
              _user!.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 4),

            // Handle
            Text(
              '@${_user!.name.toLowerCase().replaceAll(' ', '')}',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF8E8E8E),
              ),
            ),

            const SizedBox(height: 24),

            // Bio
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    _user!.bio ?? 'No bio yet',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF666666),
                      height: 1.5,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.pushNamed(context, '/edit-profile');
                      _loadProfile();
                    },
                    child: const Icon(
                      Icons.edit,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/edit-profile');
                      _loadProfile();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00AEEF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Edit Profile',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _shareProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.grey[50],
                    ),
                    child: const Text(
                      'Share Profile',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Photos Grid
            if (photos.isNotEmpty) ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _openFullscreen(index),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: photos[index],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 60),
              const Text(
                '📷',
                style: TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 16),
              Text(
                'No media yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload your first photo in edit profile',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.2),
      child: Center(
        child: Text(
          _user?.name.isNotEmpty == true ? _user!.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
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
}

// Settings Modal
class _SettingsModal extends StatelessWidget {
  final String? referralCode;
  final String? referralUrl;
  final VoidCallback onReferFriend;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _SettingsModal({
    required this.referralCode,
    required this.referralUrl,
    required this.onReferFriend,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.person_add, color: Colors.black),
          title: const Text('Refer a Friend'),
          onTap: onReferFriend,
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text(
            'Logout',
            style: TextStyle(color: Colors.red),
          ),
          onTap: onLogout,
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text(
            'Delete Account',
            style: TextStyle(color: Colors.red),
          ),
          onTap: onDeleteAccount,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// Referral Modal
class _ReferralModal extends StatelessWidget {
  final String? referralCode;
  final String? referralUrl;
  final VoidCallback onCopyLink;
  final VoidCallback onShare;

  const _ReferralModal({
    required this.referralCode,
    required this.referralUrl,
    required this.onCopyLink,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 24),
          // Illustration / Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF00AEEF).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              size: 40,
              color: Color(0xFF00AEEF),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Invite Friends, Get Rewarded',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Share your unique link. When your friends join, you both unlock premium features!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.4),
            ),
          ),
          const SizedBox(height: 32),
          // Premium Referral Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00AEEF), Color(0xFF007BBB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00AEEF).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'YOUR REFERRAL CODE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    referralCode ?? '------',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopyLink,
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    label: const Text(
                      'Copy Link',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00AEEF),
                      side: const BorderSide(color: Color(0xFF00AEEF), width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text(
                      'Share Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00AEEF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Fullscreen Image Viewer
class _FullscreenViewer extends StatelessWidget {
  final List<String> photos;
  final int initialIndex;

  const _FullscreenViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final PageController controller = PageController(initialPage: initialIndex);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: controller,
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
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  shape: BoxShape.circle,
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