import '../../core/authed_api.dart';

/// API d'enregistrement des jetons FCM — utilisé en v2 (push désactivé en v1).
class PushRepository {
  PushRepository(this._api);
  final AuthedApi _api;

  Future<void> register(String token, String platform) async {
    await _api.post("/api/push/register", {"token": token, "platform": platform});
  }

  Future<void> unregister(String token) async {
    await _api.delete("/api/push/register?token=${Uri.encodeComponent(token)}");
  }
}
