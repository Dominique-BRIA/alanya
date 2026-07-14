import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé des tokens JWT (Keychain iOS / Keystore Android).
/// Persiste après fermeture / redémarrage de l'app.
class TokenStorage {
  static const _android = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false, // ne jamais effacer silencieusement en cas d'erreur de déchiffrement
    // keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    // storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: false,
  );
  static final _storage = FlutterSecureStorage(
    aOptions: _android,
    iOptions: _ios,
  );

  static const _kAccess = "alanya_access_token";
  static const _kRefresh = "alanya_refresh_token";
  static const _kUser = "alanya_user_json";

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  // --- Profil utilisateur en cache, pour un démarrage instantané offline ---
  Future<void> saveUserJson(String json) => _storage.write(key: _kUser, value: json);
  Future<String?> get userJson => _storage.read(key: _kUser);

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
  }
}
