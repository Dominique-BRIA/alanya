import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// Logotype « ALANYA WORK » : le dernier A d'ALANYA et le mot WORK portent
/// l'accent terre cuite, comme dans le système visuel de référence.
///
/// L'accent suit le thème — terre cuite en clair, terre cuite claire en Nuit,
/// où le `#C1663F` manquerait de contraste sur le fond nuit. La couleur des
/// lettres non accentuées est héritée du contexte (`AppBar`, dialogue…), donc
/// rien à passer pour l'aligner sur l'écran qui l'accueille.
class AlanyaWordmark extends StatelessWidget {
  const AlanyaWordmark({
    super.key,
    this.fontSize = 22,
    this.letterSpacing = 2,
    this.height,
    this.color,
  });

  final double fontSize;

  /// Interlettrage. La valeur par défaut est passée de 4 à 2 avec l'ajout de
  /// « WORK » : le logotype fait désormais onze caractères au lieu de six, et
  /// l'espacement d'origine le rendait trop large pour une AppBar qui porte
  /// aussi des actions.
  final double letterSpacing;

  /// `height` de la ligne ; utile dans une `AppBar` où l'espace est contraint.
  final double? height;

  /// Couleur des lettres non accentuées. Par défaut, celle du contexte.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = TextStyle(
      color: dark ? AlanyaColors.terracottaNuitLight : AlanyaColors.terracotta,
    );
    final base = TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );

    // FittedBox plutôt qu'un simple Text : sur un écran étroit, « ALANYA WORK »
    // et les actions de l'AppBar peuvent dépasser la largeur disponible. Un
    // débordement afficherait les rayures jaunes et noires de Flutter ; ici le
    // logotype se réduit proportionnellement, ce qui reste lisible.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: "ALANY"),
            TextSpan(text: "A", style: accent),
            TextSpan(text: " WORK", style: accent),
          ],
        ),
        // Le logotype ne se traduit pas, ne se coupe pas et ne suit pas le
        // réglage de taille de police du système.
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
