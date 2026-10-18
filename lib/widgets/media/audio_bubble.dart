import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';
import 'bulle_vocale.dart';

/// Bulle d'un vocal EN CLAIR — une enveloppe de [BulleVocale], la bulle
/// commune aux vocaux en clair et chiffrés (18/10/2026).
///
/// ⚠️ [onTap] N'EST PLUS UTILISÉ : la bulle pilote elle-même le lecteur
/// (lecture, avance, vitesse). Le paramètre reste pour ne pas casser les
/// appelants.
class AudioBubble extends StatelessWidget {
  const AudioBubble({
    super.key,
    required this.url,
    this.duration,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String url;

  /// Durée en millisecondes.
  final int? duration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    // Nuit : dans une bulle reçue, l'onde et le bouton de lecture passent en
    // terre cuite claire (le seul accent chaud de la bulle). Le mode clair est
    // inchangé.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onSub =
        isMe ? Colors.white70 : (dark ? AlanyaColors.craie2 : Colors.black45);
    final accent = isMe
        ? Colors.white
        : (dark ? AlanyaColors.terracottaNuitLight : AlanyaColors.terracotta);
    return BulleVocale(
      identite: url,
      isMe: isMe,
      couleur: accent,
      couleurDiscrete: onSub,
      duree: duration == null ? null : Duration(milliseconds: duration!),
      onLongPress: onLongPress,
      obtenirSource: () async => url,
      pied: timestamp == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(timestamp!, style: TextStyle(fontSize: 11, color: onSub)),
              if (statusWidget != null) ...[
                const SizedBox(width: 3),
                statusWidget!,
              ],
            ]),
    );
  }
}
