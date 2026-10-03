import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/message.dart';
import '../screens/visionneur_vue_unique.dart';

/// LA BULLE D'UN MESSAGE À VUE UNIQUE — jamais l'image elle-même.
///
/// Elle dit ce que c'est (photo, vidéo, vocal) et où on en est :
///   - expéditeur : « Envoyée », puis « Ouverte » quand quelqu'un a vu ;
///   - destinataire : « Appuyez pour ouvrir », puis « Ouverte », grisée.
///
/// 🔴 AUCUNE VIGNETTE, ni floutée ni réduite. Une miniature est déjà une
/// vue : le serveur refuse d'ailleurs le média à quiconque ne l'a pas ouvert,
/// expéditeur compris.
class BulleVueUnique extends StatelessWidget {
  const BulleVueUnique({
    super.key,
    required this.message,
    required this.isMe,
    required this.couleurAccent,
    required this.couleurDiscrete,
    required this.timestamp,
    this.statusWidget,
    this.onOuvrir,
    this.onLongPress,
  });

  final Message message;
  final bool isMe;
  final Color couleurAccent;
  final Color couleurDiscrete;
  final String timestamp;
  final Widget? statusWidget;

  /// `null` quand il n'y a rien à ouvrir (expéditeur, déjà ouverte, effacée).
  final VoidCallback? onOuvrir;
  final VoidCallback? onLongPress;

  /// Peut-on encore l'ouvrir, depuis cet appareil ?
  static bool ouvrable(Message m, {required bool isMe}) =>
      !isMe && !m.vueUniqueOuverte && !m.vueUniqueEffacee && !m.isDeleted;

  @override
  Widget build(BuildContext context) {
    // Chiffrée, le serveur ne voit qu'un « octet-stream » : le vrai type est
    // dans le descripteur (chapitre 25).
    final type = message.mediaChiffre?.mime ??
        (message.media.isNotEmpty && !message.media.first.chiffre
            ? message.media.first.mimeType
            : null) ??
        (message.type == 'VIDEO'
            ? 'video/'
            : message.type == 'AUDIO'
                ? 'audio/'
                : 'image/');
    final (icone, cle) = type.startsWith('video/')
        ? (Icons.videocam_outlined, 'vu_video')
        : type.startsWith('audio/')
        ? (Icons.mic_none, 'vu_vocal')
        : (Icons.photo_outlined, 'vu_photo');

    final ouvrable = onOuvrir != null;
    final consommee = message.vueUniqueOuverte || message.vueUniqueEffacee;
    final couleur = ouvrable ? couleurAccent : couleurDiscrete;
    final etat = isMe
        ? tr(context, consommee ? 'vu_ouverte' : 'vu_envoyee')
        : tr(context, ouvrable ? 'vu_appuyer' : 'vu_ouverte');

    return InkWell(
      onTap: onOuvrir,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 190),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PastilleVueUnique(taille: 26, couleur: couleur),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icone, size: 16, color: couleur),
                          const SizedBox(width: 4),
                          Text(
                            tr(context, cle),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: consommee && !isMe
                                  ? couleurDiscrete
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        etat,
                        style: TextStyle(fontSize: 12, color: couleurDiscrete),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timestamp,
                    style: TextStyle(fontSize: 11, color: couleurDiscrete),
                  ),
                  if (statusWidget != null) ...[
                    const SizedBox(width: 4),
                    statusWidget!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
