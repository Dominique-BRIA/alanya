import 'dart:isolate';
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
    required String pairId,
    required String moi,
    required MediaPickResult fichier,
    String legende = '',
    String? replyToId,
    bool vueUnique = false,
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
    final f = await Isolate.run<FichierChiffre>(() => chiffrerFichier(octets));

    // 3. Le fichier chiffré : nom et type neutres.
    final envoye = await medias.upload(
      f.chiffre,
      'chiffre.bin',
      'application/octet-stream',
      chiffre: true,
    );

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

    // 5. Ma copie. On ne s'envoie pas d'enveloppe à soi-même : ce cache et
    // l'archive sont les seuls endroits où MA copie de la clé existe.
    final quand = DateTime.now();
    await MessageCache.rangeTexteDechiffre(
      id: id,
      convId: convId,
      expediteurId: moi,
      texte: legende,
      quand: quand,
      media: d,
    );
    await pile.sauvegarde.deposer([
      {
        'id': id,
        'convId': convId,
        'expediteurId': moi,
        'texte': legende,
        'quand': quand.millisecondsSinceEpoch,
        'media': d.toJson(),
      },
    ]);
    if (!vueUnique) await OuvertureMediaChiffre.garderClair(d, octets);

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
