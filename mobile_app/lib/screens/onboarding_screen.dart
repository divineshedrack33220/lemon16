import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Connect Instantly',
      description: 'Experience lightning-fast messaging with a premium glassmorphic interface designed for clarity.',
      image: 'https://images.unsplash.com/photo-1611162617474-5b21e879e113?q=80&w=1000&auto=format&fit=crop',
      color: const Color(0xFF00AEEF),
    ),
    OnboardingData(
      title: 'Nearby Magic',
      description: 'Find interesting people exactly where you are. Real-time proximity discovery at your fingertips.',
      image: 'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?q=80&w=1000&auto=format&fit=crop',
      color: const Color(0xFF6C63FF),
    ),
    OnboardingData(
      title: 'Safe & Secure',
      description: 'Your privacy is our priority. Advanced blocking and encryption keep your conversations yours.',
      image: 'https://images.unsplash.com/photo-1563986768609-322da13575f3?q=80&w=1000&auto=format&fit=crop',
      color: const Color(0xFF00C896),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Animated Background Blob
          AnimatedContainer(
            duration: const Duration(seconds: 1),
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _pages[_currentPage].color.withOpacity(0.05),
                  Colors.white,
                  _pages[_currentPage].color.withOpacity(0.1),
                ],
              ),
            ),
          ),

          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemBuilder: (context, idx) {
              return OnboardingPage(data: _pages[idx], pageIndex: idx);
            },
          ),

          // Top Progress Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 24,
            right: 24,
            child: Row(
              children: List.generate(_pages.length, (index) {
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: _currentPage >= index 
                          ? _pages[_currentPage].color 
                          : Colors.grey[200],
                    ),
                  ),
                );
              }),
            ),
          ),

          // Bottom Actions
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 30,
            left: 24,
            right: 24,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                        );
                      } else {
                        Navigator.pushNamed(context, '/signup');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pages[_currentPage].color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(
                      _currentPage == _pages.length - 1 ? 'Get Started' : 'Continue',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/login'),
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Log In',
                          style: TextStyle(
                            color: _pages[_currentPage].color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

class OnboardingData {
  final String title;
  final String description;
  final String image;
  final Color color;
  OnboardingData({required this.title, required this.description, required this.image, required this.color});
}

class OnboardingPage extends StatelessWidget {
  final OnboardingData data;
  final int pageIndex;
  const OnboardingPage({super.key, required this.data, required this.pageIndex});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 100), // Top spacing for progress bar
                  
                  // Premium Dynamic Animated Vector Illustration
                  _AnimatedIllustration(
                    pageIndex: pageIndex,
                    themeColor: data.color,
                  ),
                  
                  const SizedBox(height: 50),
                  Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    data.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 180), // Increased space for bottom actions
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedIllustration extends StatefulWidget {
  final int pageIndex;
  final Color themeColor;
  const _AnimatedIllustration({required this.pageIndex, required this.themeColor});

  @override
  State<_AnimatedIllustration> createState() => _AnimatedIllustrationState();
}

class _AnimatedIllustrationState extends State<_AnimatedIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.themeColor.withOpacity(0.06),
        boxShadow: [
          BoxShadow(
            color: widget.themeColor.withOpacity(0.03),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ],
      ),
      child: ClipOval(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _IllustrationPainter(
                pageIndex: widget.pageIndex,
                color: widget.themeColor,
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  final int pageIndex;
  final Color color;
  final double progress;

  _IllustrationPainter({
    required this.pageIndex,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (pageIndex == 0) {
      // 1. Connect Instantly: Pulsing network hub and chat bubbles
      // Concentric signal rings
      for (int i = 0; i < 3; i++) {
        final ringProgress = (progress + i / 3.0) % 1.0;
        final ringRadius = ringProgress * 110;
        final ringOpacity = (1.0 - ringProgress).clamp(0.0, 1.0);
        paint
          ..color = color.withOpacity(ringOpacity * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(center, ringRadius, paint);
      }

      // Draw connection lines
      paint
        ..color = color.withOpacity(0.25)
        ..strokeWidth = 1.5;
      final offset1 = Offset(center.dx - 50, center.dy + 35);
      final offset2 = Offset(center.dx + 45, center.dy - 50);
      canvas.drawLine(center, offset1, paint);
      canvas.drawLine(center, offset2, paint);

      // Central core
      paint
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawCircle(center, 12, paint);
      paint
        ..style = PaintingStyle.fill
        ..color = Colors.white;
      canvas.drawCircle(center, 6, paint);

      // Drifting left chat bubble
      final dyLeft = math.sin(progress * 2 * math.pi) * 10;
      final bubbleLeft = RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - 90, center.dy - 40 + dyLeft, 64, 32),
        const Radius.circular(10),
      );
      paint
        ..color = Colors.white.withOpacity(0.92)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(bubbleLeft, paint);
      paint
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawRRect(bubbleLeft, paint);
      
      // Little chat bubble tail
      final tailPathLeft = Path();
      tailPathLeft.moveTo(center.dx - 50, center.dy - 8 + dyLeft);
      tailPathLeft.lineTo(center.dx - 40, center.dy - 8 + dyLeft);
      tailPathLeft.lineTo(center.dx - 45, center.dy - 2 + dyLeft);
      tailPathLeft.close();
      paint
        ..color = Colors.white.withOpacity(0.92)
        ..style = PaintingStyle.fill;
      canvas.drawPath(tailPathLeft, paint);
      paint
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawPath(tailPathLeft, paint);

      // Dot in left bubble
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx - 58, center.dy - 24 + dyLeft), 3, paint);

      // Drifting right chat bubble
      final dyRight = math.cos(progress * 2 * math.pi) * 10;
      final bubbleRight = RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx + 25, center.dy + 10 + dyRight, 64, 32),
        const Radius.circular(10),
      );
      paint
        ..color = Colors.white.withOpacity(0.92)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(bubbleRight, paint);
      paint
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawRRect(bubbleRight, paint);
      
      // Little chat bubble tail
      final tailPathRight = Path();
      tailPathRight.moveTo(center.dx + 40, center.dy + 10 + dyRight);
      tailPathRight.lineTo(center.dx + 50, center.dy + 10 + dyRight);
      tailPathRight.lineTo(center.dx + 45, center.dy + 4 + dyRight);
      tailPathRight.close();
      paint
        ..color = Colors.white.withOpacity(0.92)
        ..style = PaintingStyle.fill;
      canvas.drawPath(tailPathRight, paint);
      paint
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawPath(tailPathRight, paint);

      // Dot in right bubble
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx + 57, center.dy + 26 + dyRight), 3, paint);

    } else if (pageIndex == 1) {
      // 2. Nearby Magic: Location radar screen
      // Radar sweeps
      paint
        ..color = color.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, 30, paint);
      canvas.drawCircle(center, 65, paint);
      canvas.drawCircle(center, 100, paint);

      // Crosshairs
      canvas.drawLine(Offset(center.dx - 110, center.dy), Offset(center.dx + 110, center.dy), paint);
      canvas.drawLine(Offset(center.dx, center.dy - 110), Offset(center.dx, center.dy + 110), paint);

      // Sweep line
      final sweepAngle = progress * 2 * math.pi;
      final sweepLine = Offset(
        center.dx + math.cos(sweepAngle) * 100,
        center.dy + math.sin(sweepAngle) * 100,
      );
      paint
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 2.2;
      canvas.drawLine(center, sweepLine, paint);

      // Pulsing nearby users dots
      final users = [
        Offset(center.dx - 35, center.dy - 40),
        Offset(center.dx + 50, center.dy + 25),
        Offset(center.dx - 55, center.dy + 50),
      ];
      final colors = [
        const Color(0xFF00AEEF),
        const Color(0xFFFFFF00),
        const Color(0xFF6C63FF),
      ];

      for (int i = 0; i < users.length; i++) {
        final pulseVal = (progress * 2 + i * 0.3) % 1.0;
        final sizeMult = 1.0 + (pulseVal * 0.8);
        final userOpacity = 1.0 - pulseVal;

        // Pulse ring
        paint
          ..color = colors[i].withOpacity(userOpacity * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(users[i], 10 * sizeMult, paint);

        // Core dot
        paint
          ..color = colors[i]
          ..style = PaintingStyle.fill;
        canvas.drawCircle(users[i], 5, paint);
      }

      // Central pulse marker
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 7, paint);

    } else {
      // 3. Safe & Secure: Shield and locks
      // Rotating ring locks
      paint
        ..color = color.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, 80, paint);

      // Draw safe notches on rotating ring
      paint
        ..color = color.withOpacity(0.4)
        ..strokeWidth = 2;
      for (int i = 0; i < 8; i++) {
        final angle = (progress * 0.5 * math.pi) + (i * math.pi / 4);
        final start = Offset(center.dx + math.cos(angle) * 75, center.dy + math.sin(angle) * 75);
        final end = Offset(center.dx + math.cos(angle) * 85, center.dy + math.sin(angle) * 85);
        canvas.drawLine(start, end, paint);
      }

      // Draw stylized shield path in center
      final shieldPath = Path();
      final width = 50.0;
      final height = 65.0;
      final topY = center.dy - 30;
      
      shieldPath.moveTo(center.dx, topY);
      shieldPath.quadraticBezierTo(center.dx + width / 2, topY, center.dx + width / 2, topY + 12);
      shieldPath.quadraticBezierTo(center.dx + width / 2, topY + height * 0.6, center.dx, topY + height);
      shieldPath.quadraticBezierTo(center.dx - width / 2, topY + height * 0.6, center.dx - width / 2, topY + 12);
      shieldPath.quadraticBezierTo(center.dx - width / 2, topY, center.dx, topY);
      shieldPath.close();

      // Pulsing shield gradient
      final pulseScale = 1.0 + (math.sin(progress * 2 * math.pi) * 0.05);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(pulseScale);
      canvas.translate(-center.dx, -center.dy);

      paint
        ..style = PaintingStyle.fill
        ..color = color.withOpacity(0.08);
      canvas.drawPath(shieldPath, paint);

      paint
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 3.0;
      canvas.drawPath(shieldPath, paint);

      // Inner lock tick
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx, center.dy - 4), 6, paint);
      paint
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx, center.dy - 4), 3, paint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pageIndex != pageIndex;
  }
}
