import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:share_handler/share_handler.dart';

/// CE QU'UNE AUTRE APPLICATION PARTAGE VERS ALANYA (07/10/2026, demande du
/// user : « Partager »).
///
/// Android nous le confie par les filtres SEND / SEND_MULTIPLE du manifeste ;
/// `share_handler` le rend ici. Même schéma que `LiensEntrants` : abonnement
/// dès le lancement (dans `main()`), consommation plus tard, par l'accueil —
/// l'écran qui sait quoi en faire n'existe qu'une fois connecté.
class PartageRecu {
  const PartageRecu({this.texte, this.fichiers = const [], this.conversationId});

  /// Un texte ou un lien.
  final String? texte;

  /// Les fichiers, déjà copiés sur l'appareil par le greffon.
  final List<String> fichiers;

  /// La conversation choisie DIRECTEMENT dans la feuille de partage (contact
  /// Alanya proposé en haut), `null` sinon — il faut alors la demander.
  final String? conversationId;

  bool get vide => (texte ?? '').trim().isEmpty && fichiers.isEmpty;
}

class PartageEntrant {
  PartageEntrant._();
  static final instance = PartageEntrant._();

  final _enAttente = ValueNotifier<PartageRecu?>(null);
  StreamSubscription<SharedMedia>? _abonnement;

  /// Le partage reçu et pas encore traité ; notifie à chaque arrivée.
  ValueListenable<PartageRecu?> get enAttente => _enAttente;

  /// À appeler une fois, dans `main()`. Sans effet hors Android.
  Future<void> demarrer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final greffon = ShareHandlerPlatform.instance;
    try {
      final initial = await greffon.getInitialSharedMedia();
      if (initial != null) {
        _recevoir(initial);
        // Sinon, il reviendrait à chaque relance de l'écran d'accueil.
        await greffon.resetInitialSharedMedia();
      }
    } catch (_) {}
    _abonnement ??= greffon.sharedMediaStream.listen(
      _recevoir,
      // Un partage illisible ne doit rien casser : il est ignoré.
      onError: (Object _) {},
    );
  }

  void _recevoir(SharedMedia m) {
    final p = PartageRecu(
      texte: m.content,
      fichiers: [
        for (final a in m.attachments ?? const <SharedAttachment?>[])
          if (a != null && a.path.isNotEmpty) a.path,
      ],
      conversationId: m.conversationIdentifier,
    );
    if (!p.vide) _enAttente.value = p;
  }

  /// Retire le partage en attente et le rend (nul s'il n'y en a pas).
  PartageRecu? prendre() {
    final p = _enAttente.value;
    _enAttente.value = null;
    return p;
  }

  /// Propose cette conversation EN HAUT de la feuille de partage d'Android
  /// (raccourci de partage). Appelé quand on écrit à quelqu'un : ce sont les
  /// conversations récentes qui remontent, comme sur WhatsApp.
  ///
  /// ⚠️ SANS IMAGE : le greffon décode l'image du disque sans vérifier le
  /// résultat, et un fichier illisible le ferait planter côté natif.
  ///
  /// ⚠️ NE LÈVE JAMAIS : Android limite le nombre de raccourcis et le rythme
  /// des mises à jour ; un refus ne doit pas gêner l'envoi du message.
  Future<void> proposerEnHaut(String convId, String nom) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await ShareHandlerPlatform.instance.recordSentMessage(
        conversationIdentifier: convId,
        conversationName: nom,
      );
    } catch (_) {}
  }
}

/// Le type MIME d'un fichier reçu par partage, d'après son extension.
///
/// ⚠️ PLUS LARGE QUE `mimeDepuisNom` (compression_envoi.dart), qui ne connaît
/// que les images et les vidéos : on peut aussi recevoir un PDF, un document
/// ou un vocal. Sans son vrai type, un PDF partirait en fichier anonyme.
String mimeFichierRecu(String nom) {
  final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
  const types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    '3gp': 'video/3gpp',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'zip': 'application/zip',
  };
  return types[ext] ?? 'application/octet-stream';
}
