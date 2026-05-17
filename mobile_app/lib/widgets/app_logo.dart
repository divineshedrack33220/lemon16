import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  
  const AppLogo({super.key, this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    final double circleSize = size * 1.2;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFF00AEEF),
            shape: BoxShape.circle,
          ),
        ),
        Image.asset(
          'assets/logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}
