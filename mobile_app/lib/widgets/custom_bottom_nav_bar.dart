import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class CustomBottomNavBar extends StatefulWidget {
  final String currentRoute;
  final int? favoritesCount;
  final int? chatsCount;

  const CustomBottomNavBar({
    super.key,
    required this.currentRoute,
    this.favoritesCount,
    this.chatsCount,
  });

  static void clearCache() {
    _CustomBottomNavBarState._cachedAvatar = null;
    _CustomBottomNavBarState._cachedName = null;
  }

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar> {
  String? _userAvatar;
  String _userName = '';
  static String? _cachedAvatar;
  static String? _cachedName;

  @override
  void initState() {
    super.initState();
    if (_cachedAvatar != null || _cachedName != null) {
      _userAvatar = _cachedAvatar;
      _userName = _cachedName ?? '';
    }
    // Always reload to keep avatar fresh
    _loadUserAvatar();
  }

  Future<void> _loadUserAvatar() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        String? avatarUrl = profile['avatar'] as String?;
        if ((avatarUrl == null || avatarUrl.isEmpty) &&
            profile['photos'] is List &&
            (profile['photos'] as List).isNotEmpty) {
          avatarUrl = (profile['photos'] as List).first as String?;
        }
        final name = profile['name'] as String? ?? '';
        setState(() {
          _userAvatar = avatarUrl;
          _userName = name;
          _cachedAvatar = _userAvatar;
          _cachedName = _userName;
        });
      }
    } catch (e) {
      // Ignore error — keep showing whatever we have
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 60.0 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              _buildNavItem(
                context,
                icon: Icons.explore,
                label: 'Live',
                route: '/feed',
                isActive: widget.currentRoute == '/feed',
              ),
              _buildNavItem(
                context,
                icon: widget.currentRoute == '/favorites' ? Icons.favorite : Icons.favorite_border,
                label: 'Favorites',
                route: '/favorites',
                isActive: widget.currentRoute == '/favorites',
                badgeCount: widget.favoritesCount,
              ),
              Expanded(child: const SizedBox()), // Space for FAB
              _buildNavItem(
                context,
                icon: widget.currentRoute == '/chats' ? Icons.chat_bubble : Icons.chat_bubble_outline,
                label: 'Chats',
                route: '/chats',
                isActive: widget.currentRoute == '/chats',
                badgeCount: widget.chatsCount,
              ),
              _buildNavItem(
                context,
                icon: widget.currentRoute == '/profile' ? Icons.person : Icons.person_outline,
                label: 'Profile',
                route: '/profile',
                isActive: widget.currentRoute == '/profile',
                isProfile: true,
              ),
            ],
          ),
          Positioned(
            top: -24,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () async {
                  if (widget.currentRoute != '/create-post') {
                    final result = await Navigator.pushNamed(context, '/create-post');
                    if (result == true) {
                      Navigator.pushReplacementNamed(context, '/feed');
                    }
                  }
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00AEEF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00AEEF).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.black,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
    required bool isActive,
    int? badgeCount,
    bool isProfile = false,
  }) {
    final color = isActive ? const Color(0xFF00AEEF) : const Color(0xFF666666);

    return Expanded(
      child: InkWell(
        onTap: () {
          if (!isActive) {
            Navigator.pushReplacementNamed(context, route);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (isProfile)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive ? const Color(0xFF00AEEF) : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _userAvatar != null && _userAvatar!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _userAvatar!,
                              fit: BoxFit.cover,
                              placeholder: (ctx, url) => _buildMonogram(color),
                              errorWidget: (ctx, url, err) => _buildMonogram(color),
                            )
                          : _buildMonogram(color),
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: color,
                    size: 26,
                  ),
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonogram(Color color) {
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.15),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
      ),
    );
  }
}

