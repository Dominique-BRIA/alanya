import 'dart:ui';

import 'package:flutter/material.dart';

/// Surface **glassmorphism** réutilisable (fond semi-transparent flouté,
/// bordure claire, ombre douce). Thème-aware : s'adapte automatiquement au
/// mode clair et au mode sombre via la `Brightness` du thème courant.
///
/// C'est le composant de base du nouveau design premium (fiche contact,
/// heads-up, cartes d'info…). Extrait pour être partagé partout.
///
/// Exemple :
/// ```dart
/// GlassCard(
///   radius: 20,
///   padding: const EdgeInsets.all(16),
///   child: Text('Contenu'),
/// )
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.blurSigma = 18,
    this.padding,
    this.margin,
    this.borderColor,
    this.glowColor,
    this.glowStrength = 0.16,
    this.onTap,
    this.fillOpacity = 1.0,
  });

  final Widget child;

  /// Rayon des coins (borderRadius élevé pour un rendu premium).
  final double radius;

  /// Intensité du flou de fond (BackdropFilter).
  final double blurSigma;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Couleur de bordure. `null` → bordure claire par défaut (thème-aware).
  final Color? borderColor;

  /// Teinte de l'ombre douce. `null` → noir. Utile pour un halo coloré.
  final Color? glowColor;

  /// Opacité de l'ombre portée.
  final double glowStrength;

  /// Rend la carte cliquable avec un effet d'encre (micro-interaction).
  final VoidCallback? onTap;

  /// Multiplicateur d'opacité du remplissage (1.0 = valeurs par défaut).
  /// < 1.0 → plus transparent (laisse davantage transparaître le flou).
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Remplissage semi-transparent + léger dégradé pour la profondeur.
    final double topA = (dark ? 0.82 : 0.80) * fillOpacity;
    final double botA = (dark ? 0.78 : 0.68) * fillOpacity;
    final Color fillTop = dark
        ? const Color(0xFF262019).withValues(alpha: topA)
        : Colors.white.withValues(alpha: topA);
    final Color fillBottom = dark
        ? const Color(0xFF1C1712).withValues(alpha: botA)
        : Colors.white.withValues(alpha: botA);
    final Color border = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.65));

    Widget inner = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fillTop, fillBottom],
        ),
        border: Border.all(color: border, width: 1),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (onTap != null) {
      inner = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: inner,
        ),
      );
    }

    // Ombre douce portée à l'EXTÉRIEUR du ClipRRect (sinon elle serait rognée).
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? Colors.black).withValues(alpha: glowStrength),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: inner,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return card;
  }
}
