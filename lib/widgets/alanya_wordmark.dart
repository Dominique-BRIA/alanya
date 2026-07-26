import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// Logotype « ALANYA » : le dernier A porte l'accent terre cuite, comme dans
/// le système visuel de référence.
///
/// L'accent suit le thème — terre cuite en clair, terre cuite claire en Nuit,
/// où le `#C1663F` manquerait de contraste sur le fond nuit. La couleur des
/// cinq premières lettres est héritée du contexte (`AppBar`, dialogue…), donc
/// rien à passer pour l'aligner sur l'écran qui l'accueille.
class AlanyaWordmark extends StatelessWidget {
  const AlanyaWordmark({
    super.key,
    this.fontSize = 22,
    this.letterSpacing = 4,
    this.height,
    this.color,
  });

  final double fontSize;
  final double letterSpacing;

  /// `height` de la ligne ; utile dans une `AppBar` où l'espace est contraint.
  final double? height;

  /// Couleur des lettres non accentuées. Par défaut, celle du contexte.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: "ALANY"),
          TextSpan(
            text: "A",
            style: TextStyle(
              color: dark
                  ? AlanyaColors.terracottaNuitLight
                  : AlanyaColors.terracotta,
            ),
          ),
        ],
      ),
      // Le logotype ne se traduit pas et ne se coupe pas.
      textScaler: TextScaler.noScaling,
    );
  }
}
