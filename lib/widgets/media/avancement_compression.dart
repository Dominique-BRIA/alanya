import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// « Compression… 42 % » — ce que montre le bouton d'envoi pendant qu'une
/// vidéo se transcode, à la place d'un simple cercle.
///
/// 🐛 « Sur le web tu as mis le pourcentage de compression ; sur le mobile ? »
/// (user, 10/10/2026). Le mobile n'affichait qu'un cercle qui tourne : pour
/// une longue vidéo, on attendait une minute sans savoir où on en était.
///
/// Avec plusieurs vidéos dans le lot, on dit laquelle : « Vidéo 2/3 · 42 % ».
/// Le pourcentage repart de zéro à chaque vidéo — sans le rang, on croirait
/// la compression revenue en arrière.
class AvancementCompression extends StatelessWidget {
  const AvancementCompression({
    super.key,
    required this.avancement,
    this.rang = 1,
    this.total = 1,
    this.style,
  });

  /// De 0 à 1.
  final double avancement;
  final int rang;
  final int total;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final pct = '${(avancement.clamp(0.0, 1.0) * 100).round()}';
    final texte = total > 1
        ? tr(context, 'compression_video_n_pct',
            {'i': '$rang', 'n': '$total', 'pct': pct})
        : tr(context, 'compression_video_pct', {'pct': pct});
    return Text(
      texte,
      maxLines: 1,
      // Les chiffres ont tous la même largeur : le bouton ne tremble pas à
      // chaque pour cent.
      style: (style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
