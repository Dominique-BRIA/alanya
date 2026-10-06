/// COMPRESSER UNE IMAGE AVANT DE L'ENVOYER.
///
/// Une photo de téléphone fait 3 à 8 Mo pour 4000 × 3000 pixels. Le fil de
/// discussion l'affiche dans 280 px de large. On payait donc — en données
/// mobiles, des DEUX côtés — le transport d'une image cinquante fois plus
/// grande que ce qui s'affiche. Sur ce produit, c'est le mobile qui paie le
/// plus cher : c'est là que la donnée se compte.
///
/// 🔴 MIROIR DART DE `STAGE-WEB/src/lib/image-compression.ts`. Les deux clients
/// doivent produire des images comparables — mêmes bornes, mêmes refus, mêmes
/// noms de fichier. Toute évolution se décide dans les deux, ou l'un des deux
/// enverra des photos deux fois plus lourdes que l'autre sans que personne
/// sache pourquoi.
///
/// ⚠️ CE MODULE PRÉFÈRE TOUJOURS NE RIEN FAIRE. Chaque incertitude — format
/// inconnu, décodage raté, gain absent — rend les octets d'origine. Une image
/// envoyée intacte est un non-événement ; une image abîmée, couchée ou vidée de
/// sa transparence est un défaut que l'utilisateur découvre chez son
/// correspondant, quand il est trop tard.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:photo_manager/photo_manager.dart';

/// Bord le plus long après réduction. Repère WhatsApp ; un grand téléphone
/// affiche environ 1290 px physiques.
const int imageBordMax = 1600;

/// Qualité JPEG, sur 100. `0.82` côté web — même valeur, autre échelle.
const int imageQualite = 82;

/// En dessous, le gain ne vaut pas le risque de perte : on garde l'original.
const double gainMinimum = 0.9;

/// Poids au-delà duquel une image DÉJÀ PETITE est quand même ré-encodée.
///
/// Une photo passée par ici pèse 0,1 à 0,3 octet par pixel : elle reste sous
/// ce seuil, et ne perd donc pas un peu de qualité à chaque transfert. Une
/// image de 1500 px enregistrée en qualité maximale en pèse 1 à 2 — elle passe.
/// Même valeur que `OCTETS_PAR_PIXEL_MAX` côté web.
const double octetsParPixelMax = 0.5;

/// Pourquoi la compression n'a rien fait. Sert au diagnostic, pas à l'affichage.
enum RaisonSaut {
  pasUneImage,
  tropPetite,

  /// Un pixel au moins est transparent : en JPEG, il deviendrait noir.
  transparente,
  animee,
  decodageImpossible,
  sansGain,
}

class ResultatCompression {
  const ResultatCompression({
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
  final RaisonSaut? raisonSaut;

  /// Ce que l'envoi a économisé, entre 0 et 1. Sert à l'annoncer à l'écran.
  double get gain =>
      tailleAvant <= 0 ? 0 : 1 - (tailleApres / tailleAvant);
}

/// Compresse l'image d'un `AssetEntity` de la galerie, ou rend l'original.
///
/// ⚠️ PASSE PAR `thumbnailDataWithSize` PLUTÔT QUE PAR UN PAQUET DE
/// COMPRESSION. Le décodage et le ré-encodage se font dans le code natif déjà
/// embarqué par `photo_manager` : aucune dépendance de plus, donc aucun risque
/// pour les trois chaînes d'intégration — et l'orientation EXIF est appliquée
/// par la plateforme, alors qu'elle nous aurait coûté le plus délicat du code
/// côté web (une photo couchée est le défaut classique de ce chemin).
Future<ResultatCompression> compresserAsset(
  AssetEntity asset,
  Uint8List original, {
  required String nomFichier,
  required String mimeType,
}) async {
  ResultatCompression intact(RaisonSaut raison) => ResultatCompression(
        octets: original,
        nomFichier: nomFichier,
        mimeType: mimeType,
        compresse: false,
        tailleAvant: original.length,
        tailleApres: original.length,
        raisonSaut: raison,
      );

  if (asset.type != AssetType.image) return intact(RaisonSaut.pasUneImage);

  // Le format se lit dans les OCTETS : le type déclaré vient du nom du
  // fichier, et une capture d'écran renommée ou sans extension le trompe.
  final png = _signature(original, const [0x89, 0x50, 0x4e, 0x47]);
  final gif = _signature(original, const [0x47, 0x49, 0x46, 0x38]);
  // Un GIF perdrait son animation en devenant une image fixe.
  if (gif || mimeType.toLowerCase().contains("gif")) {
    return intact(RaisonSaut.animee);
  }

  /*
   * 🐛 LES CAPTURES D'ÉCRAN PARTAIENT INTACTES (signalé par le user le
   * 06/10/2026 : « ça ne compresse pas »). Ce module laissait passer TOUT PNG,
   * au nom de la transparence. Or le PNG est d'abord le format des captures —
   * 400 Ko à 1 Mo pour un écran de téléphone, cinq fois le poids du même
   * écran en JPEG. Seuls l'animé et le transparent restent intacts, et ils
   * sont reconnus un par un. Même règle que le web, le même jour.
   */
  if (png) {
    final refus = await pngIntouchable(original);
    if (refus != null) return intact(refus);
  }

  var largeur = asset.width;
  var hauteur = asset.height;
  /*
   * 🐛 DIMENSIONS INCONNUES (06/10/2026, photo envoyée depuis le mobile « trop
   * lourde »). Android rend souvent 0 × 0 pour une photo que la galerie n'a
   * pas encore indexée — typiquement celle qu'on vient de prendre et qu'on
   * envoie aussitôt. On les lit alors dans l'en-tête du fichier, sans le
   * décoder.
   */
  if (largeur <= 0 || hauteur <= 0) {
    final lues = await _dimensions(original);
    if (lues != null) {
      largeur = lues.$1;
      hauteur = lues.$2;
    }
  }
  final bordLong = math.max(largeur, hauteur);

  /*
   * ⚠️ UNE IMAGE DÉJÀ PETITE ET LÉGÈRE N'EST PAS RECOMPRESSÉE. C'est ce qui
   * empêche une photo reçue puis transférée de perdre un peu de qualité à
   * chaque saut, jusqu'à devenir la photocopie de photocopie que tout le monde
   * reconnaît. Le PNG n'est jamais dans ce cas : il n'est pas encore passé par
   * ici, puisque ce module rend du JPEG.
   */
  if (!png &&
      bordLong > 0 &&
      bordLong <= imageBordMax &&
      original.length <= largeur * hauteur * octetsParPixelMax) {
    return intact(RaisonSaut.tropPetite);
  }

  Uint8List? reduit;
  try {
    reduit = await asset.thumbnailDataWithSize(
      consigneVignette(largeur, hauteur),
      format: ThumbnailFormat.jpeg,
      quality: imageQualite,
    );
  } catch (_) {
    // HEIC exotique, fichier tronqué, mémoire insuffisante : on ne sait pas le
    // lire, on n'y touche pas. Le serveur, lui, accepte l'original tel quel.
    return intact(RaisonSaut.decodageImpossible);
  }
  if (reduit == null || reduit.isEmpty) {
    return intact(RaisonSaut.decodageImpossible);
  }
  if (reduit.length >= original.length * gainMinimum) {
    return intact(RaisonSaut.sansGain);
  }

  /*
   * LE NOM ET LE TYPE SUIVENT LES OCTETS, ET CE N'EST PAS DE LA COQUETTERIE.
   *
   * Le serveur choisit l'extension de stockage d'après le NOM du fichier avant
   * de regarder le type. Envoyer des octets JPEG sous un nom `.png` les ferait
   * servir plus tard avec le mauvais en-tête, et certains navigateurs refusent
   * alors de les afficher. Même règle que le web, mot pour mot.
   */
  return ResultatCompression(
    octets: reduit,
    nomFichier: _enJpg(nomFichier),
    mimeType: "image/jpeg",
    compresse: true,
    tailleAvant: original.length,
    tailleApres: reduit.length,
  );
}

/*
 * LA CONSIGNE DE TAILLE À DONNER À `thumbnailDataWithSize`, pour que le BORD
 * LONG sorte à [imageBordMax] — et qu'aucune image ne soit jamais agrandie.
 *
 * 🐛 ANDROID AGRANDISSAIT (trouvé le 06/10/2026). Le paquet y passe par Glide,
 * qui, sans transformation, REMPLIT le cadre demandé : c'est le bord COURT qui
 * prend la consigne. Une photo 4000 × 3000 sortait donc en 2133 × 1600, et une
 * capture 1080 × 2400 serait ressortie en 1600 × 3556 — agrandie, plus lourde
 * que l'original. Un cadre carré dont le côté vaut le bord court visé donne le
 * bon résultat quelle que soit l'orientation de l'image.
 *
 * iOS, lui, AJUSTE l'image dans le cadre : c'est le bord long qui prend la
 * consigne.
 */
@visibleForTesting
ThumbnailSize consigneVignette(int largeur, int hauteur, {bool? android}) {
  final long = math.max(largeur, hauteur);
  final court = math.min(largeur, hauteur);
  if (long <= 0 || court <= 0) {
    return const ThumbnailSize(imageBordMax, imageBordMax);
  }
  final facteur = math.min(1.0, imageBordMax / long);
  final cote = (android ?? Platform.isAndroid)
      ? math.max(1, (court * facteur).round())
      : math.max(1, (long * facteur).round());
  return ThumbnailSize(cote, cote);
}

bool _signature(Uint8List octets, List<int> attendus) {
  if (octets.length < attendus.length) return false;
  for (var i = 0; i < attendus.length; i++) {
    if (octets[i] != attendus[i]) return false;
  }
  return true;
}

/// Un PNG qu'il ne faut PAS convertir en JPEG — animé ou transparent —, ou
/// `null` s'il peut l'être.
///
/// Dans le doute, on répond « intouchable » : une capture qui part en PNG est
/// un peu lourde, un logo qui arrive sur fond noir est un défaut.
@visibleForTesting
Future<RaisonSaut?> pngIntouchable(Uint8List octets) async {
  // APNG : la norme place `acTL` AVANT le premier `IDAT`. Flutter ne décode
  // pas toujours l'animation : on ne s'en remet pas à son décompte d'images.
  final vue = ByteData.sublistView(octets);
  var position = 8;
  var idatAtteint = false;
  while (position + 8 <= vue.lengthInBytes) {
    final longueur = vue.getUint32(position);
    final type = String.fromCharCodes(octets, position + 4, position + 8);
    if (type == "acTL") return RaisonSaut.animee;
    if (type == "IDAT") {
      idatAtteint = true;
      break;
    }
    position += 12 + longueur;
  }
  if (!idatAtteint) return RaisonSaut.decodageImpossible;

  /*
   * Transparence : on décode en PETIT (256 px de large suffisent — un pixel
   * transparent le reste une fois réduit) et l'on cherche un alpha < 255. Une
   * capture d'écran est entièrement opaque, même quand son PNG prévoit une
   * couche alpha.
   */
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(octets, targetWidth: 256);
    if (codec.frameCount > 1) return RaisonSaut.animee;
    image = (await codec.getNextFrame()).image;
    final donnees = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (donnees == null) return RaisonSaut.decodageImpossible;
    final pixels = donnees.buffer
        .asUint8List(donnees.offsetInBytes, donnees.lengthInBytes);
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] < 255) return RaisonSaut.transparente;
    }
    return null;
  } catch (_) {
    return RaisonSaut.decodageImpossible;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Largeur et hauteur lues dans l'EN-TÊTE, sans décoder les pixels.
Future<(int, int)?> _dimensions(Uint8List octets) async {
  ui.ImmutableBuffer? tampon;
  ui.ImageDescriptor? descripteur;
  try {
    tampon = await ui.ImmutableBuffer.fromUint8List(octets);
    descripteur = await ui.ImageDescriptor.encoded(tampon);
    final l = descripteur.width;
    final h = descripteur.height;
    return l > 0 && h > 0 ? (l, h) : null;
  } catch (_) {
    return null;
  } finally {
    descripteur?.dispose();
    tampon?.dispose();
  }
}

String _enJpg(String nom) {
  final point = nom.lastIndexOf('.');
  final base = point > 0 ? nom.substring(0, point) : nom;
  return "$base.jpg";
}

/// « 4,2 Mo », « 320 Ko » — pour annoncer le gain à l'utilisateur.
String poidsLisible(int octets) {
  if (octets < 1024) return "$octets o";
  if (octets < 1024 * 1024) {
    return "${(octets / 1024).toStringAsFixed(0)} Ko";
  }
  return "${(octets / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo";
}
