import 'package:flutter/material.dart';

class LemonBottomNav extends StatelessWidget {
  final int currentIndex;
  
  const LemonBottomNav({super.key, this.currentIndex = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _NavItem(
              icon: Icons.explore,
              label: 'Live',
              isActive: currentIndex == 0,
              onTap: () {
                if (currentIndex != 0) {
                  Navigator.pushReplacementNamed(context, '/feed');
                }
              },
            ),
            _NavItem(
              icon: Icons.favorite_border,
              label: 'Favorites',
              isActive: currentIndex == 1,
              onTap: () {
                if (currentIndex != 1) {
                  Navigator.pushReplacementNamed(context, '/favorites');
                }
              },
            ),
            const SizedBox(width: 48),
            _NavItem(
              icon: Icons.chat_bubble_outline,
              label: 'Chats',
              isActive: currentIndex == 2,
              onTap: () {
                if (currentIndex != 2) {
                  Navigator.pushReplacementNamed(context, '/chats');
                }
              },
            ),
            _NavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              isActive: currentIndex == 3,
              onTap: () {
                if (currentIndex != 3) {
                  Navigator.pushReplacementNamed(context, '/profile');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFF00AEEF) : const Color(0xFF999999),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? const Color(0xFF00AEEF) : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
