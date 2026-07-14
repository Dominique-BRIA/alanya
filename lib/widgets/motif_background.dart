import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fond décoratif réutilisant le motif africain d'Alanya, avec un voile crème
/// par-dessus pour garder le contenu lisible.
class MotifBackground extends StatelessWidget {
  const MotifBackground({super.key, required this.child, this.overlayOpacity = 0.88});

  final Widget child;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            "assets/images/motif_bg.png",
            repeat: ImageRepeat.repeat,
            // Si l'asset manque, on retombe sur un fond crème uni.
            errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.cream),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: AppColors.cream.withValues(alpha: overlayOpacity)),
        ),
        child,
      ],
    );
  }
}
