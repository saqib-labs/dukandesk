import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base diagonal mesh gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE4F1F5), Color(0xFFF3F5F0), Color(0xFFFCEEE4)],
              stops: [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Large soft teal blob, top-left
        Positioned(
          top: -80,
          left: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(0.14),
                  AppColors.primary.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        // Gold blob, mid-right
        Positioned(
          top: 220,
          right: -70,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.accent.withOpacity(0.16),
                  AppColors.accent.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        // Small teal accent blob, lower-left
        Positioned(
          bottom: 60,
          left: -40,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(0.10),
                  AppColors.primary.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
