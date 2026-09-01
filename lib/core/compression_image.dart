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

import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// Bord le plus long après réduction. Repère WhatsApp ; un grand téléphone
/// affiche environ 1290 px physiques.
const int imageBordMax = 1600;

/// Qualité JPEG, sur 100. `0.82` côté web — même valeur, autre échelle.
const int imageQualite = 82;

/// En dessous, le gain ne vaut pas le risque de perte : on garde l'original.
const double gainMinimum = 0.9;

/// Pourquoi la compression n'a rien fait. Sert au diagnostic, pas à l'affichage.
enum RaisonSaut {
  pasUneImage,
  tropPetite,
  png,
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

  final type = mimeType.toLowerCase();
  // Un GIF perdrait son animation en devenant une image fixe, et un PNG sa
  // transparence : les deux ressortiraient sur fond noir chez le correspondant.
  if (type.contains("gif")) return intact(RaisonSaut.animee);
  if (type.contains("png")) return intact(RaisonSaut.png);

  /*
   * ⚠️ TEST SUR LES DIMENSIONS, PAS SUR LE POIDS. C'est lui qui empêche de
   * recompresser indéfiniment une image déjà passée par ici : une photo reçue
   * puis transférée perdrait un peu de qualité à chaque saut, jusqu'à devenir
   * la photocopie de photocopie que tout le monde reconnaît.
   */
  final bordLong =
      asset.width > asset.height ? asset.width : asset.height;
  if (bordLong <= 0) return intact(RaisonSaut.decodageImpossible);
  if (bordLong <= imageBordMax) return intact(RaisonSaut.tropPetite);

  Uint8List? reduit;
  try {
    reduit = await asset.thumbnailDataWithSize(
      const ThumbnailSize(imageBordMax, imageBordMax),
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
