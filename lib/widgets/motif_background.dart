import 'package:flutter/material.dart';
import '../theme/alanya_theme.dart';

/// Fond décoratif réutilisant le motif africain d'Alanya, avec un voile
/// par-dessus pour garder le contenu lisible.
///
/// Mode Nuit — d'après le système visuel : le motif habille les surfaces
/// immersives (fil de discussion, en-têtes) sous un **dégradé descendant**,
/// mais les listes et les écrans de réglages restent en surfaces pleines,
/// « sans bruit derrière le texte » → passer [plainInDark] à `true`.
/// Le mode clair n'est pas affecté par [plainInDark].
class MotifBackground extends StatelessWidget {
  const MotifBackground({
    super.key,
    required this.child,
    this.overlayOpacity = 0.88,
    this.plainInDark = false,
  });

  final Widget child;
  final double overlayOpacity;
  final bool plainInDark;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Nuit + surface pleine : fond uni, aucun motif derrière le texte.
    if (dark && plainInDark) {
      return Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: AlanyaColors.nuit)),
          child,
        ],
      );
    }

    if (dark) {
      // Motif « doux » sous un dégradé descendant : lisible en haut,
      // contraste renforcé en bas (là où arrivent les bulles).
      return Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/motif_nuit_doux.png",
              repeat: ImageRepeat.repeat,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: AlanyaColors.nuit),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AlanyaColors.nuit.withValues(alpha: 0.45),
                    AlanyaColors.nuit.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      );
    }

    // Mode clair : motif terre cuite + voile crème (inchangé).
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            "assets/images/motif_bg.png",
            repeat: ImageRepeat.repeat,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: AlanyaColors.cream),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: AlanyaColors.cream.withValues(alpha: overlayOpacity),
          ),
        ),
        child,
      ],
    );
  }
}
