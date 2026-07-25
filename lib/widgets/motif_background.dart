import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// Fond décoratif réutilisant le motif africain d'Alanya, avec un voile crème
/// par-dessus pour garder le contenu lisible.
class MotifBackground extends StatelessWidget {
  const MotifBackground({super.key, required this.child, this.overlayOpacity = 0.88});

  final Widget child;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Mode nuit : motif « doux » (déjà sombre et subtil) + voile léger nuit.
    // Mode clair : motif terre cuite + voile crème.
    final asset =
        dark ? "assets/images/motif_nuit_doux.png" : "assets/images/motif_bg.png";
    final veil = dark ? AlanyaColors.nuit : AlanyaColors.cream;
    final veilOpacity = dark ? 0.55 : overlayOpacity;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            asset,
            repeat: ImageRepeat.repeat,
            errorBuilder: (_, __, ___) => ColoredBox(color: veil),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: veil.withValues(alpha: veilOpacity)),
        ),
        child,
      ],
    );
  }
}
