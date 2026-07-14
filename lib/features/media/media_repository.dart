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
  }) async {
    final data = await _api.uploadBytes(
      "/api/media",
      bytes,
      filename,
      mimeType,
      fields: durationMs != null ? {"durationMs": "$durationMs"} : null,
    );
    return UploadedMedia(
      id: data["id"] as String,
      url: data["url"] as String,
      mimeType: data["mimeType"] as String,
    );
  }
}
