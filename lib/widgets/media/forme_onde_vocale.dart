import 'package:flutter/material.dart';

import '../../core/formes_onde_commun.dart';

/// La forme d'onde d'un message vocal : la partie écoutée en couleur pleine,
/// le reste estompé. Un toucher ou un glissé avance l'écoute — comme Talky
/// (`VoiceWaveformBar`) et WhatsApp.
class FormeOndeVocale extends StatelessWidget {
  const FormeOndeVocale({
    super.key,
    required this.barres,
    required this.progression,
    required this.couleur,
    this.onAvance,
  });

  final List<double> barres;

  /// De 0 (rien d'écouté) à 1 (tout).
  final double progression;
  final Color couleur;

  /// Appelé avec la position touchée, de 0 à 1. Absent : pas d'avance.
  final ValueChanged<double>? onAvance;

  @override
  Widget build(BuildContext context) {
    final donnees =
        barres.isEmpty ? List<double>.filled(barresFormeOnde, 0.35) : barres;
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final largeur = c.maxWidth;
      void avance(Offset p) =>
          onAvance?.call((p.dx / largeur).clamp(0.0, 1.0).toDouble());
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onAvance == null ? null : (d) => avance(d.localPosition),
        onHorizontalDragUpdate:
            onAvance == null ? null : (d) => avance(d.localPosition),
        child: SizedBox(
          height: 28,
          width: largeur,
          child: CustomPaint(
            painter: _Peintre(
              barres: donnees,
              progression: progression.clamp(0.0, 1.0).toDouble(),
              actif: couleur,
              inactif: couleur.withAlpha(sombre ? 60 : 85),
            ),
          ),
        ),
      );
    });
  }
}

class _Peintre extends CustomPainter {
  _Peintre({
    required this.barres,
    required this.progression,
    required this.actif,
    required this.inactif,
  });

  final List<double> barres;
  final double progression;
  final Color actif;
  final Color inactif;

  @override
  void paint(Canvas canvas, Size size) {
    final n = barres.length;
    if (n == 0) return;
    const ecart = 1.5;
    final largeurBarre = (size.width - ecart * (n - 1)) / n;
    final max = barres.reduce((a, b) => a > b ? a : b);
    final echelle = max <= 0 ? 1.0 : 1.0 / max;
    final limite = size.width * progression;
    for (var i = 0; i < n; i++) {
      final x = i * (largeurBarre + ecart);
      final h = (barres[i] * echelle).clamp(0.08, 1.0) * size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, largeurBarre, h),
        const Radius.circular(1.2),
      );
      canvas.drawRRect(
          rect, Paint()..color = x + largeurBarre / 2 <= limite ? actif : inactif);
    }
  }

  @override
  bool shouldRepaint(covariant _Peintre ancien) =>
      ancien.progression != progression ||
      ancien.barres != barres ||
      ancien.actif != actif ||
      ancien.inactif != inactif;
}
