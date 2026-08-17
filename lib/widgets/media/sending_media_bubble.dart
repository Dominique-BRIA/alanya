import 'package:flutter/material.dart';

import '../../features/chat/envoi_media.dart';
import '../../theme/alanya_theme.dart';

/// Bulle d'un envoi de médias EN COURS ou ÉCHOUÉ.
///
/// Elle apparaît dès la validation, avec la vignette locale : l'utilisateur voit
/// ce qu'il envoie avant que le réseau n'ait rien fait. Avant, le fil restait
/// vide jusqu'au retour du serveur.
///
/// Trois états, trois affichages — parce qu'ils appellent trois réactions
/// différentes de la part de l'utilisateur :
///   - en cours   : anneau de progression et « 2/8 », rien à faire ;
///   - à 100 %    : « Envoi… » sans pourcentage, car les octets sont partis mais
///                  le serveur n'a pas encore répondu (voir `ApiClient`) ;
///   - échoué     : la raison, puis « Réessayer » ou « Supprimer ».
class SendingMediaBubble extends StatelessWidget {
  const SendingMediaBubble({
    super.key,
    required this.envoi,
    required this.onReessayer,
    required this.onAbandonner,
    this.legende,
    this.isMe = true,
  });

  final EnvoiMedia envoi;
  final VoidCallback onReessayer;
  final VoidCallback onAbandonner;
  final String? legende;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final apercu = envoi.apercu;
    final estImage = apercu != null && apercu.mimeType.startsWith('image/');
    final surfaces = surfacesOf(context);
    final onText = isMe ? surfaces.texteBulleEnvoyee : surfaces.texteBulleRecue;
    final onSub = isMe ? Colors.white70 : AlanyaColors.grey500;

    return SizedBox(
      width: 236,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 236,
                  height: 160,
                  child: estImage
                      ? Image.memory(apercu.bytes, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: Center(
                            child: Icon(
                              apercu != null &&
                                      apercu.mimeType.startsWith('video/')
                                  ? Icons.movie_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 42,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                ),
                // Voile : sans lui, l'anneau blanc disparaît sur une photo
                // claire — et c'est justement là qu'il doit rester lisible.
                Container(color: Colors.black.withValues(alpha: 0.35)),
                if (envoi.echoue)
                  const Icon(Icons.error_outline, size: 40, color: Colors.white)
                else
                  _anneau(),
              ],
            ),
          ),
          if (envoi.total > 1) ...[
            const SizedBox(height: 4),
            Text(
              envoi.echoue
                  ? "${envoi.mediaIdsObtenus.length}/${envoi.total} envoyé${envoi.mediaIdsObtenus.length > 1 ? "s" : ""}"
                  : "Envoi ${envoi.indexCourant + 1}/${envoi.total}",
              style: TextStyle(fontSize: 11.5, color: onSub),
            ),
          ],
          if (envoi.echoue) ...[
            const SizedBox(height: 2),
            Text(
              envoi.erreur ?? "Échec de l'envoi",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: isMe ? Colors.white : dangerOf(context)),
            ),
            const SizedBox(height: 2),
            Row(children: [
              _action(context,
                  icone: Icons.refresh, label: "Réessayer", onTap: onReessayer),
              const SizedBox(width: 4),
              _action(context,
                  icone: Icons.delete_outline,
                  label: "Supprimer",
                  onTap: onAbandonner),
            ]),
          ] else if (envoi.progression >= 1) ...[
            const SizedBox(height: 3),
            // Les octets sont partis, la réponse du serveur ne l'est pas : on
            // n'écrit donc PAS « terminé », qui serait un mensonge.
            Text("Envoi…", style: TextStyle(fontSize: 11.5, color: onSub)),
          ],
          if ((legende ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(legende!,
                style: TextStyle(fontSize: 14, color: onText),
                maxLines: 6,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _anneau() {
    final valeur = envoi.progression;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          // Indéterminé au tout début : une barre figée à 0 % ressemble à un
          // envoi bloqué, alors que la connexion s'établit encore.
          value: valeur <= 0.01 ? null : valeur,
          strokeWidth: 3,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        ),
        if (valeur > 0.01 && valeur < 1)
          Text("${(valeur * 100).round()}",
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _action(BuildContext context,
      {required IconData icone,
      required String label,
      required VoidCallback onTap}) {
    final couleur = isMe ? Colors.white : accentOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: couleur)),
        ]),
      ),
    );
  }
}
