import '../../core/authed_api.dart';
import '../../models/status.dart';

class StatusRepository {
  StatusRepository(this._api);
  final AuthedApi _api;

  Future<StatusFeed> feed() async {
    final data = await _api.get("/api/statuses");
    return StatusFeed.fromJson(data);
  }

  /// Publie un statut texte avec couleur de fond (hex #RRGGBB).
  Future<void> createText(String text, String bgColor) async {
    await _api.post("/api/statuses", {
      "type": "TEXT",
      "text": text,
      "bgColor": bgColor,
    });
  }

  /// Publie un statut média (image ou vidéo) via l'ID d'un média déjà uploadé.
  Future<void> createMedia(String mediaId, String type) async {
    await _api.post("/api/statuses", {
      "type": type,
      "mediaId": mediaId,
    });
  }

  Future<void> markViewed(String statusId) async {
    await _api.post("/api/statuses/$statusId/view", {});
  }

  /// Liste des personnes ayant vu mon statut ({userId, name, avatarUrl, viewedAt}).
  Future<List<Map<String, dynamic>>> getViews(String statusId) async {
    final data = await _api.get("/api/statuses/$statusId/views");
    return ((data["views"] as List?) ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<void> delete(String statusId) async {
    await _api.delete("/api/statuses/$statusId");
  }
}
