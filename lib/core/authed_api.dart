import 'dart:typed_data';

import 'api_client.dart';
import 'token_storage.dart';
import 'verrou_rafraichissement.dart';

/// Enveloppe l'ApiClient pour injecter automatiquement l'access token et
/// rafraîchir la session une fois en cas de 401.
///
/// ⚠️ UN VERROU sur le rafraîchissement empêche les requêtes concurrentes d'en
/// lancer plusieurs en parallèle — ce qui révoquerait prématurément le jeton
/// (rotation serveur) et provoquait des déconnexions.
///
/// ⚠️ CE VERROU N'EST PLUS LOCAL À CETTE CLASSE. Il vit dans
/// [VerrouRafraichissement] et couvre désormais TOUS les chemins, y compris
/// `AuthController.bootstrap()` qui se rafraîchissait de son côté.
class AuthedApi {
  AuthedApi(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  Future<Map<String, dynamic>> get(String path) =>
      _withAuth((token) => _api.get(path, bearer: token));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _withAuth((token) => _api.post(path, body, bearer: token));

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _withAuth((token) => _api.patch(path, body, bearer: token));

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _withAuth((token) => _api.put(path, body, bearer: token));

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body}) =>
      _withAuth((token) => _api.delete(path, bearer: token, body: body));

  /// ⚠️ [onProgress] peut REPARTIR DE ZÉRO : sur 401, `_withAuth` rafraîchit la
  /// session et rejoue la requête entière, donc le compteur recommence. L'appelant
  /// doit afficher le dernier ratio reçu, jamais supposer qu'il ne décroît pas.
  Future<Map<String, dynamic>> uploadBytes(
    String path,
    Uint8List bytes,
    String filename,
    String mimeType, {
    Map<String, String>? fields,
    void Function(int envoyes, int total)? onProgress,
  }) =>
      _withAuth((token) => _api.uploadBytes(path, bytes, filename, mimeType,
          bearer: token, fields: fields, onProgress: onProgress));

  /// Upload EN FLUX depuis un fichier (voir `api_client.uploadFile`). Même
  /// rejeu sur 401 que [uploadBytes] : le fichier étant relu depuis le disque,
  /// le second essai repart proprement de zéro.
  Future<Map<String, dynamic>> uploadFile(
    String path,
    String filePath,
    String filename,
    String mimeType, {
    Map<String, String>? fields,
    void Function(int envoyes, int total)? onProgress,
  }) =>
      _withAuth((token) => _api.uploadFile(path, filePath, filename, mimeType,
          bearer: token, fields: fields, onProgress: onProgress));

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

  /// Refresh protégé par un verrou : un seul à la fois, les autres attendent.
  ///
  /// ⚠️ LE VERROU EST DÉSORMAIS PARTAGÉ avec `AuthController.bootstrap()`, qui
  /// se rafraîchissait de son côté sans rien savoir de celui-ci. Au démarrage,
  /// les deux partaient ensemble avec le MÊME jeton, et la rotation serveur en
  /// condamnait un — la session tombait alors que rien n'avait expiré.
  Future<String?> _refreshLocked() async {
    try {
      return await VerrouRafraichissement.partage(_doRefresh);
    } catch (_) {
      // Ici, on ne juge pas : `_withAuth` relaie l'erreur d'origine et c'est
      // `AuthController` qui lit le code du serveur pour décider du sort de la
      // session. Voir `sessionMorteApresEchec`.
      return null;
    }
  }

  Future<String?> _doRefresh() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null) return null;
    final data = await _api.post("/api/auth/refresh", {"refreshToken": refresh});
    final access = data["accessToken"] as String;
    final newRefresh = data["refreshToken"] as String;
    // ⚠️ ÉCRIT AVANT DE RENDRE LA MAIN. Si l'application est tuée entre la
    // rotation côté serveur et cette écriture, le jeton en mémoire est déjà
    // mort et seul l'ancien subsiste sur le disque : c'est exactement le cas
    // que la fenêtre de grâce du serveur rattrape.
    await _storage.saveTokens(access: access, refresh: newRefresh);
    return access;
  }
}
