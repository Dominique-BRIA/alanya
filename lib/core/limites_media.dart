import 'dart:typed_data';

/// LES BORNES DES MÉDIAS, EN UN SEUL ENDROIT.
///
/// La valeur « 50 Mo » était écrite en dur dans `media_picker_sheet.dart`, et
/// n'était appliquée QU'À UN chemin d'envoi sur quatre. Les trois autres
/// laissaient partir n'importe quelle taille : l'utilisateur payait le
/// téléversement de 60 Mo pour recevoir un refus du serveur à l'arrivée.
///
/// ⚠️ CETTE VALEUR DOIT RESTER ÉGALE À TROIS AUTRES :
///   - `backend-alanya/src/lib/env.ts` → `MEDIA_MAX_SIZE_MB` (la seule qui
///     fasse foi : c'est elle qui refuse) ;
///   - `STAGE-WEB/src/services/media-service.ts` → `TAILLE_MEDIA_MAX_MO` ;
///   - et la configuration `client_max_body_size` de nginx sur le serveur.
/// Changer l'une sans les autres fait mentir celles qui restent.
class LimitesMedia {
  const LimitesMedia._();

  static const int tailleMaxMo = 50;
  static const int tailleMaxOctets = tailleMaxMo * 1024 * 1024;

  /// Bord le plus long d'une image après réduction.
  ///
  /// Même valeur que le web (`IMAGE_BORD_MAX`). Les trois clients n'exécutent
  /// pas le même code, mais ils doivent produire le MÊME RÉSULTAT : sans quoi
  /// la même photo pèse 300 Ko envoyée d'un côté et 4 Mo de l'autre, et
  /// personne ne comprend pourquoi.
  static const int imageBordMax = 1600;

  /// Qualité JPEG, sur 100. Équivaut au 0,82 du web.
  static const int imageQualite = 85;

  /// Ce fichier tient-il dans la limite ?
  static bool tientDansLaLimite(Uint8List octets) =>
      octets.length <= tailleMaxOctets;

  /// Poids lisible, pour un message d'erreur — « 63,4 Mo ».
  static String enMo(int octets) =>
      '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
}
