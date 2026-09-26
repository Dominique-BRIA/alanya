/// COMPRESSER UNE VIDÉO AVANT DE L'ENVOYER.
///
/// Une vidéo de téléphone sort en 1080p — souvent en 4K — à 20 Mo la minute et
/// plus. Un statut la montre dans un écran de téléphone, pendant 60 secondes au
/// plus. On payait donc, en données mobiles et des DEUX côtés, le transport
/// d'un fichier plusieurs fois plus lourd que ce qui s'affiche. C'est le même
/// raisonnement que pour les photos, et c'est le pendant vidéo de
/// `core/compression_image.dart`.
///
/// ⚠️ CE MODULE PRÉFÈRE TOUJOURS NE RIEN FAIRE, comme son jumeau côté image.
/// Chaque incertitude — pas de chemin de fichier, dimensions inconnues,
/// transcodage refusé, gain absent — rend la vidéo d'origine. Une vidéo
/// envoyée intacte est un non-événement ; une vidéo muette, retournée ou
/// tronquée est un défaut que l'utilisateur découvre chez son correspondant.
///
/// 🔴 IL N'Y A PAS DE MIROIR WEB. Le client web n'a aucun écran de statuts, et
/// aucun navigateur ne transcode de vidéo sans bibliothèque tierce. Si un jour
/// le web publie des statuts, ce sera une décision à prendre, pas une règle à
/// recopier.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

/// Bord le plus long visé après transcodage.
///
/// 720p est le repère de WhatsApp pour un statut. Le paquet expose la consigne
/// en clair (`Res1280x720Quality`) plutôt qu'un « moyen » dont personne ne
/// connaît la définition — même esprit que le `imageBordMax` des photos.
const int videoBordMax = 720;

/// En dessous, le gain ne vaut pas le risque de perte : on garde l'original.
const double gainMinimumVideo = 0.9;

/// Pourquoi la compression n'a rien fait. Sert au diagnostic, pas à l'affichage.
enum RaisonSautVideo {
  pasUneVideo,

  /// Le média n'a pas de fichier sur le disque : le transcodage travaille sur
  /// un chemin, pas sur des octets en mémoire.
  sansFichier,

  /// On n'a pas pu lire les dimensions, donc pas su si elle valait le coup.
  dimensionsInconnues,

  /// Déjà à 720p ou moins.
  dejaPetite,

  /// Le transcodage a échoué, ou a été refusé par le module natif.
  transcodageImpossible,

  sansGain,
}

class ResultatCompressionVideo {
  const ResultatCompressionVideo({
    required this.octets,
    required this.nomFichier,
    required this.mimeType,
    required this.compresse,
    required this.tailleAvant,
    required this.tailleApres,
    this.raisonSaut,
  });

  /// Les octets à envoyer — CEUX D'ORIGINE si rien n'a été fait.
  final Uint8List octets;
  final String nomFichier;
  final String mimeType;
  final bool compresse;
  final int tailleAvant;
  final int tailleApres;
  final RaisonSautVideo? raisonSaut;

  /// Ce que l'envoi a économisé, entre 0 et 1.
  double get gain => tailleAvant <= 0 ? 0 : 1 - (tailleApres / tailleAvant);
}

/// Transcode la vidéo de [chemin] en 720p, ou rend [original] tel quel.
///
/// [original] est indispensable : c'est la porte de sortie de chaque refus.
///
/// ⚠️ UNE SEULE COMPRESSION À LA FOIS. Le paquet lève un `StateError` si une
/// autre est en cours — et, défaut connu de sa version 3.1.4, il ne remet pas
/// son drapeau à zéro quand le transcodage échoue. Une panne rend donc les
/// suivantes impossibles pour le reste de la session : elles ressortent
/// simplement `transcodageImpossible`, et les vidéos partent intactes. C'est
/// une dégradation, jamais un blocage.
Future<ResultatCompressionVideo> compresserVideo(
  Uint8List original, {
  required String? chemin,
  required String nomFichier,
  required String mimeType,
}) async {
  ResultatCompressionVideo intact(RaisonSautVideo raison) =>
      ResultatCompressionVideo(
        octets: original,
        nomFichier: nomFichier,
        mimeType: mimeType,
        compresse: false,
        tailleAvant: original.length,
        tailleApres: original.length,
        raisonSaut: raison,
      );

  if (!mimeType.toLowerCase().startsWith("video/")) {
    return intact(RaisonSautVideo.pasUneVideo);
  }
  if (chemin == null || chemin.isEmpty) {
    return intact(RaisonSautVideo.sansFichier);
  }

  /*
   * ⚠️ TEST SUR LES DIMENSIONS, PAS SUR LE POIDS — même raison que pour les
   * photos : c'est lui qui empêche de transcoder indéfiniment une vidéo déjà
   * passée par ici. Une vidéo reçue puis repartagée perdrait un peu de qualité
   * à chaque saut.
   */
  int? bordLong;
  try {
    final info = await VideoCompress.getMediaInfo(chemin);
    final l = info.width ?? 0;
    final h = info.height ?? 0;
    if (l > 0 && h > 0) bordLong = l > h ? l : h;
  } catch (_) {
    // Fichier illisible par le module natif : on n'y touche pas.
  }
  if (bordLong == null) return intact(RaisonSautVideo.dimensionsInconnues);
  if (bordLong <= videoBordMax) return intact(RaisonSautVideo.dejaPetite);

  MediaInfo? reduit;
  try {
    reduit = await VideoCompress.compressVideo(
      chemin,
      quality: VideoQuality.Res1280x720Quality,
      // 🔴 JAMAIS `deleteOrigin` : le fichier d'origine est celui de la
      // GALERIE de l'utilisateur. Le supprimer effacerait sa vidéo.
      deleteOrigin: false,
      includeAudio: true,
    );
  } catch (_) {
    return intact(RaisonSautVideo.transcodageImpossible);
  }

  final produit = reduit?.path;
  if (produit == null || produit.isEmpty) {
    return intact(RaisonSautVideo.transcodageImpossible);
  }

  final fichier = File(produit);
  Uint8List octets;
  try {
    octets = await fichier.readAsBytes();
  } catch (_) {
    return intact(RaisonSautVideo.transcodageImpossible);
  } finally {
    // Le transcodage laisse son fichier dans le cache de l'application. Une
    // vidéo de statut pèse plusieurs mégaoctets : on ne les garde pas.
    try {
      await fichier.delete();
    } catch (_) {}
  }

  if (octets.isEmpty) return intact(RaisonSautVideo.transcodageImpossible);
  if (octets.length >= original.length * gainMinimumVideo) {
    return intact(RaisonSautVideo.sansGain);
  }

  /*
   * LE NOM ET LE TYPE SUIVENT LES OCTETS, comme pour les photos : le serveur
   * choisit l'extension de stockage d'après le NOM avant de regarder le type.
   * Le module natif rend toujours du MP4, quel que soit le conteneur d'entrée
   * — un `.mov` transcodé qui garderait son nom serait servi plus tard avec le
   * mauvais en-tête.
   */
  return ResultatCompressionVideo(
    octets: octets,
    nomFichier: _enMp4(nomFichier),
    mimeType: "video/mp4",
    compresse: true,
    tailleAvant: original.length,
    tailleApres: octets.length,
  );
}

String _enMp4(String nom) {
  final point = nom.lastIndexOf('.');
  final base = point > 0 ? nom.substring(0, point) : nom;
  return "$base.mp4";
}
