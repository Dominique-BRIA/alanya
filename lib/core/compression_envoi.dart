/// COMPRESSER UN MÉDIA DE LA GALERIE AVANT DE L'ENVOYER DANS UNE DISCUSSION.
///
/// Un seul point d'entrée pour les deux sélecteurs de la discussion — la
/// galerie plein écran et la grille des médias récents. Ils appliquaient
/// chacun leur règle à la main, et une même photo partait réduite ou entière
/// selon l'endroit où on l'avait touchée.
///
/// 🐛 LES VIDÉOS DE DISCUSSION PARTAIENT INTACTES (signalé par le user le
/// 06/10/2026 : « rassure-toi que les images et les vidéos sont bel et bien
/// compressées à l'envoi »). `compresserVideo` existait, mais seuls les
/// statuts l'appelaient : une vidéo de 1080p partait en discussion avec tous
/// ses mégaoctets.
library;

import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:video_compress/video_compress.dart';

import 'compression_image.dart';
import 'compression_video.dart';

/// Compresse [octets] selon leur genre, ou les rend tels quels.
///
/// [chemin] est indispensable à une vidéo : le transcodage lit un fichier,
/// jamais des octets en mémoire. Sans lui, elle part intacte.
///
/// [onProgression] reçoit l'avancement d'une compression VIDÉO, de 0 à 1 —
/// pour l'afficher (« Compression… 42 % »), comme le web. Une photo se
/// compresse en un instant et n'en donne pas.
///
/// Ne lève jamais : un envoi ne doit pas échouer parce qu'une optimisation a
/// échoué.
Future<ResultatCompression> compresserPourEnvoi({
  AssetEntity? asset,
  required Uint8List octets,
  required String nomFichier,
  required String mimeType,
  String? chemin,
  void Function(double avancement)? onProgression,
}) async {
  final intact = ResultatCompression(
    octets: octets,
    nomFichier: nomFichier,
    mimeType: mimeType,
    compresse: false,
    tailleAvant: octets.length,
    tailleApres: octets.length,
  );
  try {
    if (mimeType.toLowerCase().startsWith("video/")) {
      // Le module natif annonce son avancement de 0 à 100 ; les statuts s'en
      // servent déjà pour leur barre (`publication_statuts.dart`).
      final abonnement = onProgression == null
          ? null
          : VideoCompress.compressProgress$.subscribe((p) {
              onProgression((p / 100).clamp(0.0, 1.0).toDouble());
            });
      final ResultatCompressionVideo v;
      try {
        v = await compresserVideo(
          octets,
          chemin: chemin,
          nomFichier: nomFichier,
          mimeType: mimeType,
        );
      } finally {
        abonnement?.unsubscribe();
      }
      return ResultatCompression(
        octets: v.octets,
        nomFichier: v.nomFichier,
        mimeType: v.mimeType,
        compresse: v.compresse,
        tailleAvant: v.tailleAvant,
        tailleApres: v.tailleApres,
      );
    }
    if (asset != null && asset.type == AssetType.image) {
      return await compresserAsset(
        asset,
        octets,
        nomFichier: nomFichier,
        mimeType: mimeType,
      );
    }
  } catch (_) {
    // Une panne de compression laisse partir l'original, jamais rien.
  }
  return intact;
}

/// Le type MIME d'un fichier d'après son nom — pour rendre à l'original son
/// type quand l'utilisateur renonce à la compression.
///
/// ⚠️ Sans lui, une capture `.png` retrouvée partirait étiquetée
/// `image/jpeg`, et une vidéo `.mov` `video/mp4` : le serveur et le
/// correspondant liraient des octets sous le mauvais en-tête.
String mimeDepuisNom(String nom, {required String repli}) {
  final point = nom.lastIndexOf('.');
  if (point < 0) return repli;
  switch (nom.substring(point + 1).toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case '3gp':
      return 'video/3gpp';
    case 'webm':
      return 'video/webm';
    default:
      return repli;
  }
}
