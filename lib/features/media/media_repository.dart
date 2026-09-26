import 'dart:typed_data';

import '../../core/authed_api.dart';

/// CE QUE CE FICHIER VA SERVIR — ET DONC OÙ LE SERVEUR VA LE RANGER.
///
/// 🔴 DEUX USAGES SEULEMENT, ET LA LISTE EST CLOSE. Un accueil de répondeur et
/// une sonnerie sont entendus par TOUS ceux qui appellent : les publier ne
/// dévoile rien qui ne le soit déjà, et leur adresse devient FIXE — donc mise
/// en cache. C'est ce qui permet à l'accueil de partir à l'instant où la
/// sonnerie s'arrête, sans une seule requête.
///
/// ⚠️ RIEN D'AUTRE NE DOIT PORTER D'USAGE. Un message laissé PAR quelqu'un sur
/// un répondeur est un enregistrement privé ; une photo de discussion aussi. Le
/// serveur refuse d'ailleurs tout usage qu'il ne connaît pas et range en privé —
/// mais la première protection, c'est de ne pas l'écrire ici.
enum UsageMedia {
  accueil("accueil"),
  sonnerie("sonnerie");

  const UsageMedia(this.valeur);

  /// Ce que le serveur attend dans le champ `usage` du formulaire.
  final String valeur;
}

/// Résultat d'un upload média.
class UploadedMedia {
  final String id;
  final String url; // /api/media/:id

  /// L'adresse FIXE du fichier, quand il est parti dans le bucket ouvert.
  ///
  /// `null` dans tous les autres cas — et c'est le cas normal : la quasi-totalité
  /// des médias reste privée. Ne jamais la lire sans repli sur [url].
  final String? urlPublique;

  final String mimeType;
  UploadedMedia({
    required this.id,
    required this.url,
    required this.mimeType,
    this.urlPublique,
  });
}

class MediaRepository {
  MediaRepository(this._api);
  final AuthedApi _api;

  Future<UploadedMedia> upload(
    Uint8List bytes,
    String filename,
    String mimeType, {
    int? durationMs,
    UsageMedia? usage,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final data = await _api.uploadBytes(
      "/api/media",
      bytes,
      filename,
      mimeType,
      fields: {
        if (durationMs != null) "durationMs": "$durationMs",
        // Sans `usage`, le fichier va dans le stockage PRIVÉ — le bon défaut.
        // Le nommer est un choix délibéré, jamais un oubli.
        if (usage != null) "usage": usage.valeur,
      },
      onProgress: onProgress,
    );
    return UploadedMedia(
      id: data["id"] as String,
      url: data["url"] as String,
      urlPublique: data["urlPublique"] as String?,
      mimeType: data["mimeType"] as String,
    );
  }

  /// Comme [upload], mais lit le fichier EN FLUX depuis le disque — sans le
  /// charger en mémoire. À utiliser pour tout média dont la taille n'est pas
  /// bornée (enregistrements d'appel notamment).
  Future<UploadedMedia> uploadFromFile(
    String filePath,
    String filename,
    String mimeType, {
    int? durationMs,
    UsageMedia? usage,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final data = await _api.uploadFile(
      "/api/media",
      filePath,
      filename,
      mimeType,
      fields: {
        if (durationMs != null) "durationMs": "$durationMs",
        // Sans `usage`, le fichier va dans le stockage PRIVÉ — le bon défaut.
        // Le nommer est un choix délibéré, jamais un oubli.
        if (usage != null) "usage": usage.valeur,
      },
      onProgress: onProgress,
    );
    return UploadedMedia(
      id: data["id"] as String,
      url: data["url"] as String,
      urlPublique: data["urlPublique"] as String?,
      mimeType: data["mimeType"] as String,
    );
  }
}
