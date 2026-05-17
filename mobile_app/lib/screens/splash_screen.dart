import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  int _currentPhraseIndex = 0;
  bool _isVisible = true;
  
  final List<String> _phrases = [
    "Connect in Realtime",
    "Meet nearby people instantly",
    "Real-time social discovery",
    "Hang out now",
  ];

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );
    
    _animationController.forward();
    
    // Start tagline rotation
    _startTaglineRotation();
    
    // Check auth status after initialization
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _startTaglineRotation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
        
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _currentPhraseIndex = (_currentPhraseIndex + 1) % _phrases.length;
              _isVisible = true;
            });
            
            _startTaglineRotation(); // Continue rotation
          }
        });
      }
    });
  }

  Future<void> _checkAuthStatus() async {
    // Wait a bit for the splash animation
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    try {
      final token = await ApiService.getToken();
      
      if (token == null) {
        _navigateToLogin();
        return;
      }
      
      // Validate token with backend
      try {
        final profile = await ApiService.getProfile();
        
        if (profile.containsKey('_id') || profile.containsKey('id')) {
          // Token is valid, redirect to feed
          _navigateToFeed();
        } else {
          // Token invalid
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
          _navigateToLogin();
        }
      } catch (e) {
        // Network error - try cached session
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('userId');
        
        if (userId != null) {
          _navigateToFeed();
        } else {
          _navigateToLogin();
        }
      }
    } catch (e) {
      _navigateToLogin();
    }
    
    // Fallback redirect after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _navigateToLogin();
      }
    });
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/onboarding');
  }

  void _navigateToFeed() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/feed');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final paddingVal = math.max(8.0, screenWidth * 0.05);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingVal, vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with blue circle background
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: _buildLogo(),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Animated tagline
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: _isVisible ? 0.9 : 0.0,
                    child: _buildTagline(_phrases[_currentPhraseIndex]),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Loading spinner
                  _buildLoader(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 140,
      height: 140,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Blue circle background
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFF00AEEF),
              shape: BoxShape.circle,
            ),
          ),
          // Logo image
          Image.asset(
            'assets/logo.png',
            width: 70,
            height: 70,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildTagline(String phrase) {
    final words = phrase.split(' ');
    final highlightCount = words.length < 3 ? words.length : 3;
    
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 20,
          color: Color(0xFF666666),
          height: 1.45,
          letterSpacing: 0.3,
        ),
        children: List.generate(words.length, (index) {
          if (index < highlightCount) {
            // Highlight first 3 words (or fewer)
            return TextSpan(
              text: '${words[index]} ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF00AEEF),
              ),
            );
          } else {
            return TextSpan(text: '${words[index]} ');
          }
        }),
      ),
    );
  }

  Widget _buildLoader() {
    return SizedBox(
      width: 48,
      height: 48,
      child: CustomPaint(
        painter: _LoaderPainter(),
      ),
    );
  }
}

// Custom painter for the double-ring loader animation
class _LoaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    
    // First ring
    final paint1 = Paint()
      ..color = const Color(0xFF00AEEF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(center, maxRadius * 0.5, paint1);
    
    // Second ring
    final paint2 = Paint()
      ..color = const Color(0xFF00AEEF).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(center, maxRadius * 0.75, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Alternative simpler loader using existing widgets
class _SimpleLoader extends StatefulWidget {
  @override
  _SimpleLoaderState createState() => _SimpleLoaderState();
}

class _SimpleLoaderState extends State<_SimpleLoader> with SingleTickerProviderStateMixin {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00AEEF),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}