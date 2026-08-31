import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'limites_media.dart';

/// COMPRESSER UNE PHOTO AVANT DE L'ENVOYER.
///
/// Une photo d'un téléphone courant fait 3 à 5 Mo pour 4000 × 3000 pixels. La
/// bulle de conversation l'affiche dans quelques centaines de pixels. On payait
/// donc — en forfait mobile, des deux côtés — le transport d'une image
/// cinquante fois plus grande que ce qui s'affiche.
///
/// ⚠️ `imageQuality` DE `image_picker` NE SUFFIT PAS, et c'est le piège de ce
/// dossier : sans `maxWidth` / `maxHeight`, il ne fait que RÉ-ENCODER. Une
/// photo de 12 mégapixels reste en 4000 × 3000, simplement un peu moins nette.
/// Le gain vient de la RÉSOLUTION, pas de la qualité.
///
/// AUCUN PAQUET NOUVEAU : `photo_manager` sait déjà produire un JPEG redimensionné
/// à partir d'un média de la galerie.
///
/// Comme sur le web, ce module PRÉFÈRE TOUJOURS NE RIEN FAIRE : à la moindre
/// incertitude il rend les octets d'origine. Une image envoyée intacte est un
/// non-événement ; une image abîmée est un défaut que l'utilisateur découvre
/// chez son correspondant, quand il est trop tard.
class PreparationMedia {
  const PreparationMedia._();

  /// En dessous, le gain ne vaut pas le risque : on garde l'original.
  static const double _gainMinimum = 0.9;

  /// Formats qu'on ne touche JAMAIS.
  ///
  /// Le GIF et le WebP animé perdraient leur animation — on renverrait un film
  /// fixe. Le PNG perdrait sa transparence, et c'est aussi le format des
  /// captures d'écran, où le texte doit rester net. Même règle que le web.
  static bool _formatIntouchable(String nom, String mime) {
    final n = nom.toLowerCase();
    return mime == 'image/png' ||
        mime == 'image/gif' ||
        mime == 'image/webp' ||
        mime == 'image/svg+xml' ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.svg');
  }

  /// Réduit une image de la galerie, ou rend `null` s'il ne faut rien changer.
  ///
  /// Ne lève jamais : un envoi ne doit pas échouer parce qu'une optimisation a
  /// échoué.
  static Future<Uint8List?> compresserDepuisGalerie(
    AssetEntity asset,
    Uint8List original, {
    required String nomFichier,
    required String mimeType,
  }) async {
    if (asset.type != AssetType.image) return null;
    if (_formatIntouchable(nomFichier, mimeType)) return null;

    // ⚠️ LE SAUT SE DÉCIDE SUR LES DIMENSIONS, PAS SUR LE POIDS. C'est lui qui
    // empêche la recompression en cascade : une photo reçue puis transférée
    // perdrait un peu de netteté à chaque saut.
    final bordLong =
        asset.width > asset.height ? asset.width : asset.height;
    if (bordLong <= 0 || bordLong <= LimitesMedia.imageBordMax) return null;

    try {
      final facteur = LimitesMedia.imageBordMax / bordLong;
      final largeur = (asset.width * facteur).round();
      final hauteur = (asset.height * facteur).round();

      // `thumbnailDataWithSize` rend du JPEG redimensionné en respectant
      // l'orientation enregistrée — ce qu'un dessin manuel sur canevas perdrait.
      final reduit = await asset.thumbnailDataWithSize(
        ThumbnailSize(largeur, hauteur),
        quality: LimitesMedia.imageQualite,
      );
      if (reduit == null || reduit.isEmpty) return null;

      // Une réduction qui ne réduit pas ne mérite pas la perte de qualité.
      if (reduit.length >= original.length * _gainMinimum) return null;

      return reduit;
    } catch (_) {
      // Format illisible, mémoire insuffisante, média retiré entre-temps :
      // on envoie l'original plutôt que rien.
      return null;
    }
  }

  /// Le nom qui accompagne des octets JPEG.
  ///
  /// Le serveur choisit l'extension de stockage d'après le NOM avant de
  /// regarder le type déclaré : laisser un `.heic` sur des octets JPEG les
  /// ferait resservir plus tard avec le mauvais en-tête, et certains lecteurs
  /// refusent alors de les afficher.
  static String nomEnJpeg(String nom) {
    final point = nom.lastIndexOf('.');
    final base = point > 0 ? nom.substring(0, point) : nom;
    return '$base.jpg';
  }
}
