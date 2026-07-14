import 'dart:typed_data';

import 'api_client.dart';
import 'token_storage.dart';

/// Enveloppe l'ApiClient pour injecter automatiquement l'access token et
/// rafraîchir la session une fois en cas de 401.
///
/// ⚠️ Un MUEX (verrou) sur le refresh empêche les requêtes concurrentes de
/// lancer plusieurs refreshs en parallèle — ce qui révoquerait prématurément
/// le refresh token (rotation serveur) et causerait des déconnexions 401.
class AuthedApi {
  AuthedApi(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  // Mutex : un seul refresh à la fois. Les autres requêtes attendent le résultat.
  static Future<String?>? _refreshInFlight;

  Future<Map<String, dynamic>> get(String path) =>
      _withAuth((token) => _api.get(path, bearer: token));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _withAuth((token) => _api.post(path, body, bearer: token));

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _withAuth((token) => _api.patch(path, body, bearer: token));

  Future<Map<String, dynamic>> delete(String path) =>
      _withAuth((token) => _api.delete(path, bearer: token));

  Future<Map<String, dynamic>> uploadBytes(
    String path,
    Uint8List bytes,
    String filename,
    String mimeType, {
    Map<String, String>? fields,
  }) =>
      _withAuth((token) =>
          _api.uploadBytes(path, bytes, filename, mimeType, bearer: token, fields: fields));

  Future<Map<String, dynamic>> _withAuth(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    var token = await _storage.accessToken;
    if (token == null) throw ApiException(401, "Session expirée");
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;

      // --- Refresh synchronisé (mutex) ---
      // Si un refresh est déjà en cours, on attend son résultat au lieu d'en
      // lancer un nouveau. Évite la révocation prématurée du refresh token.
      final refreshed = await _refreshLocked();

      if (refreshed == null) rethrow;

      // Réessaie avec le nouveau token.
      return call(refreshed);
    }
  }

  /// Refresh protégé par un mutex : un seul à la fois, les autres attendent.
  Future<String?> _refreshLocked() async {
    // Si un refresh est déjà en cours, on attend le même Future.
    if (_refreshInFlight != null) {
      return _refreshInFlight;
    }

    // Lance le refresh et stocke le Future pour les autres appelants.
    _refreshInFlight = _doRefresh();
    try {
      return await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<String?> _doRefresh() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null) return null;
    try {
      final data = await _api.post("/api/auth/refresh", {"refreshToken": refresh});
      final access = data["accessToken"] as String;
      final newRefresh = data["refreshToken"] as String;
      await _storage.saveTokens(access: access, refresh: newRefresh);
      return access;
    } catch (_) {
      // Ne PAS effacer les tokens ici : on garde le cache pour le mode offline.
      // La déconnexion se fera via AuthController si bootstrap() échoue.
      return null;
    }
  }
}
