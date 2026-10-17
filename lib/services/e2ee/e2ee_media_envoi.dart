import 'dart:typed_data';

import '../../core/message_cache.dart';
import '../../features/media/media_repository.dart';
import '../../models/message.dart';
import '../../widgets/media/media_picker_sheet.dart' show MediaPickResult;
import 'e2ee_apercus.dart';
import 'e2ee_fournisseur.dart';
import 'e2ee_media.dart';
import 'e2ee_media_ouverture.dart';

/// ENVOYER UN MÉDIA CHIFFRÉ DEPUIS LE TÉLÉPHONE — cours, chapitre 25 (lot C).
///
/// Jumeau de `envoyerMediaChiffre` côté web, dans le même ordre et pour les
/// mêmes raisons :
///
///   1. l'APERÇU, tant que le fichier est en clair ;
///   2. le CHIFFREMENT, dans un isolat (une vidéo de 50 Mo en Dart pur figerait
///      l'écran plusieurs secondes) ;
///   3. le TÉLÉVERSEMENT du fichier chiffré, marqué `chiffre=1` ;
///   4. la LIGNE DU MESSAGE puis les ENVELOPPES (`E2eeFil.envoyerMedia`) ;
///   5. MA COPIE : cache local, archive, et clair du fichier — sauf pour une
///      vue unique, qui ne doit rien laisser derrière elle.
///
/// ⚠️ PAS DE FILE HORS LIGNE : celle des médias ordinaires renverrait le
/// fichier par le chemin ordinaire, EN CLAIR. Une coupure lève ; l'écran
/// affiche l'échec et l'utilisateur renvoie.
class EnvoiMediaChiffre {
  EnvoiMediaChiffre._();

  static Future<Message> envoyer({
    required PileE2ee pile,
    required MediaRepository medias,
    required String convId,
    /// `null` pour un GROUPE chiffré (lot 3).
    required String? pairId,
    required String moi,
    required MediaPickResult fichier,
    String legende = '',
    String? replyToId,
    bool vueUnique = false,
    /// Avancement du TÉLÉVERSEMENT, de 0 à 1 — la seule étape longue dont on
    /// connaît la taille. Avant (aperçu, chiffrement) : 0 ; après (ligne et
    /// enveloppes) : 1.
    void Function(double ratio)? onProgression,
  }) async {
    final octets = fichier.bytes;
    final mime = fichier.mimeType;

    // 1. Aperçu.
    final apercu = await fabriquerApercu(
      octets,
      mime,
      chemin: fichier.path,
      dureeMs: fichier.durationMs,
    );

    // 2. Chiffrement, hors du fil de l'écran.
    final f = await chiffrerHorsDuFil(octets);

    // 3. Le fichier chiffré : nom et type neutres.
    final envoye = await medias.upload(
      f.chiffre,
      'chiffre.bin',
      'application/octet-stream',
      chiffre: true,
      onProgress: onProgression == null
          ? null
          : (envoyes, total) =>
              onProgression(total > 0 ? envoyes / total : 0),
    );
    onProgression?.call(1);

    final d = DescripteurMedia(
      id: envoye.id,
      cle: f.cle,
      empreinte: f.empreinte,
      taille: octets.length,
      mime: mime,
      nom: fichier.fileName,
      largeur: apercu.largeur,
      hauteur: apercu.hauteur,
      dureeMs: apercu.dureeMs,
      pages: apercu.pages,
      apercu: apercu.apercu,
    );

    // 4. Ligne du message et enveloppes.
    final id = await pile.fil.envoyerMedia(
      convId: convId,
      pairId: pairId,
      media: d,
      legende: legende,
      replyToId: replyToId,
      vueUnique: vueUnique,
    );

    // 5. Ma copie.
    return rangerMaCopie(
      pile: pile,
      convId: convId,
      moi: moi,
      id: id,
      d: d,
      legende: legende,
      replyToId: replyToId,
      vueUnique: vueUnique,
      octets: octets,
    );
  }

  /// MA COPIE d'un média chiffré que je viens d'envoyer : cache local,
  /// archive, clair du fichier — sauf pour une vue unique, qui ne doit rien
  /// laisser derrière elle. Rend le message tel que le fil l'affiche.
  ///
  /// Partagée par l'envoi d'un seul bloc ([envoyer]) et l'envoi en morceaux
  /// (`envoi_morceaux_chiffre.dart`) : on ne s'envoie pas d'enveloppe à
  /// soi-même, ce cache et l'archive sont les seuls endroits où MA copie de la
  /// clé existe — les deux chemins doivent la ranger à l'identique.
  static Future<Message> rangerMaCopie({
    required PileE2ee pile,
    required String convId,
    required String moi,
    required String id,
    required DescripteurMedia d,
    required String legende,
    String? replyToId,
    bool vueUnique = false,
    /// Le clair, pour le garder en cache. Nul quand il y est déjà : renvoi par
    /// le chemin ordinaire d'un média dont la publication différée a été
    /// refusée — même descripteur, même clé de cache.
    Uint8List? octets,
  }) async {
    final quand = DateTime.now();
    await MessageCache.rangeTexteDechiffre(
      id: id,
      convId: convId,
      expediteurId: moi,
      texte: legende,
      quand: quand,
      media: d,
      replyToId: replyToId,
    );
    await pile.sauvegarde.deposer([
      {
        'id': id,
        'convId': convId,
        'expediteurId': moi,
        'texte': legende,
        'quand': quand.millisecondsSinceEpoch,
        'media': d.toJson(),
        if (replyToId != null) 'reponseA': replyToId,
      },
    ]);
    if (!vueUnique && octets != null) {
      await OuvertureMediaChiffre.garderClair(d, octets);
    }

    return Message(
      id: id,
      convId: convId,
      senderId: moi,
      content: legende,
      type: typeMessagePour(d),
      status: 'SENT',
      replyToId: replyToId,
      media: [MessageMedia.fromJson(ligneMediaChiffre(d))],
      createdAt: quand,
      chiffre: true,
      vueUnique: vueUnique,
      mediaChiffre: d,
    );
  }
}

/// Pour l'appelant qui n'a que des octets (vocal) : la même forme.
MediaPickResult fichierDepuisOctets(
  Uint8List octets,
  String nom,
  String mime, {
  int? dureeMs,
}) => MediaPickResult(
  bytes: octets,
  fileName: nom,
  mimeType: mime,
  durationMs: dureeMs,
);
