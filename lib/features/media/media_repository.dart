import 'dart:typed_data';

import '../../core/authed_api.dart';

/// Résultat d'un upload média.
class UploadedMedia {
  final String id;
  final String url; // /api/media/:id
  final String mimeType;
  UploadedMedia({required this.id, required this.url, required this.mimeType});
}

class MediaRepository {
  MediaRepository(this._api);
  final AuthedApi _api;

  Future<UploadedMedia> upload(
    Uint8List bytes,
    String filename,
    String mimeType, {
    int? durationMs,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final data = await _api.uploadBytes(
      "/api/media",
      bytes,
      filename,
      mimeType,
      fields: durationMs != null ? {"durationMs": "$durationMs"} : null,
      onProgress: onProgress,
    );
    return UploadedMedia(
      id: data["id"] as String,
      url: data["url"] as String,
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
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final data = await _api.uploadFile(
      "/api/media",
      filePath,
      filename,
      mimeType,
      fields: durationMs != null ? {"durationMs": "$durationMs"} : null,
      onProgress: onProgress,
    );
    return UploadedMedia(
      id: data["id"] as String,
      url: data["url"] as String,
      mimeType: data["mimeType"] as String,
    );
  }
}
