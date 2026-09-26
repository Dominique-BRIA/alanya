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

  /*
   * ═══ MIROIR EN MÉMOIRE DU JETON D'ACCÈS ═══
   *
   * 🔴 UNE LECTURE DE COFFRE N'EST PAS GRATUITE — ELLE PEUT NE JAMAIS REVENIR.
   * `read` traverse le canal de plateforme et se met en file derrière TOUTES
   * les écritures en cours, y compris celles d'un autre service. Un écran qui
   * attend cette lecture tourne indéfiniment alors que la valeur est connue
   * depuis le démarrage de l'app : c'est exactement le « chargement infini à
   * l'ouverture d'une conversation ».
   *
   * ⚠️ LE COFFRE RESTE LA SOURCE DE VÉRITÉ. Le miroir ne devine rien : il ne
   * retient que ce qui a été lu ou écrit ICI, est rempli par `saveTokens` et
   * par la première lecture, et vidé par `clear`.
   *
   * ⚠️ SEUL LE JETON D'ACCÈS EST MIROITÉ. Le jeton de rafraîchissement reste
   * lu dans le coffre à chaque fois, et ce n'est pas un oubli : il TOURNE à
   * chaque rafraîchissement, et un autre isolat (pousses, géolocalisation en
   * tâche de fond) peut le tourner sans que celui-ci le voie. Un miroir y
   * rendrait un jeton déjà consommé — donc un rafraîchissement refusé, donc une
   * session que plus rien ne relève. L'accès, lui, a le droit d'être périmé une
   * fois : `AuthedApi` retente après un 401.
   */
  static String? _miroirAccess;
  static bool _accessDejaVu = false;
  static Future<String?>? _accessEnCours;

  /// Version du miroir : ce qu'il tient EST cette valeur, ou rien.
  ///
  /// ⚠️ INCRÉMENTÉE À CHAQUE ÉCRITURE, et c'est ce qui ferme la dernière fenêtre
  /// de ce fichier. Une lecture en vol peut rendre un jeton que le coffre ne
  /// tient déjà plus — un rafraîchissement d'`AuthedApi` parti entre-temps, ou
  /// une déconnexion. Sans ce numéro, elle écrirait cette valeur périmée dans le
  /// miroir, et le miroir la garderait : une session morte que plus rien ne
  /// rattrape, sinon redémarrer l'application.
  static int _version = 0;

  /// Le jeton d'accès — sans traverser le coffre quand on le connaît déjà.
  ///
  /// ⚠️ LES LECTURES CONCURRENTES PARTAGENT UNE SEULE TRAVERSÉE. Au démarrage,
  /// une dizaine d'écrans réclament le jeton dans le même tour de boucle ; sans
  /// ce partage, ils empilent dix lectures derrière la même file — et c'est
  /// précisément la file qu'on veut épargner.
  ///
  /// ⚠️ UNE LECTURE QUI ÉCHOUE NE FIGE RIEN : `_accessDejaVu` reste faux, la
  /// prochaine relira. Un échec du canal ne doit pas se lire « pas de session ».
  Future<String?> get accessToken {
    if (_accessDejaVu) return Future.value(_miroirAccess);
    final enCours = _accessEnCours;
    if (enCours != null) return enCours;

    final version = _version;
    final lecture = _storage.read(key: _kAccess).then((value) {
      // Le coffre a répondu : retenu seulement s'il n'a pas été touché depuis
      // que cette lecture est partie.
      if (version == _version) {
        _miroirAccess = value;
        _accessDejaVu = true;
      }
      return value;
    }).whenComplete(() => _accessEnCours = null);

    _accessEnCours = lecture;
    return lecture;
  }

  /// Le jeton lu DIRECTEMENT dans le coffre, miroir court-circuité.
  ///
  /// ⚠️ POUR LES SEULS CHEMINS QUI NE PEUVENT PAS TOLÉRER UN JETON PÉRIMÉ :
  /// une URL de téléchargement porte le jeton en clair et ne repartira jamais
  /// après un 401 — contrairement aux requêtes d'`AuthedApi`. Elle paie
  /// l'attente du coffre, et c'est le juste prix.
  Future<String?> get accessTokenFrais => _storage.read(key: _kAccess);

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
    // QU'APRÈS que le coffre a répondu : retenir en mémoire une valeur que le
    // disque n'a pas acceptée fabrique une session que le redémarrage suivant
    // démentirait. La version change ici pour la même raison de sens opposé :
    // une lecture partie AVANT cette écriture rend une valeur que le coffre a
    // déjà tournée — la voilà disqualifiée, elle n'entrera pas dans le miroir.
    _miroirAccess = access;
    _accessDejaVu = true;
    _accessEnCours = null;
    _version++;
  }

  Future<String?> get refreshToken => _storage.read(key: _kRefresh);

  // --- Profil utilisateur en cache, pour un démarrage instantané offline ---
  Future<void> saveUserJson(String json) => _storage.write(key: _kUser, value: json);
  Future<String?> get userJson => _storage.read(key: _kUser);

  Future<void> clear() async {
    // La version change AVANT la suppression : une lecture partie avant cet
    // appel rendra bien sa valeur à qui l'attend, mais ne la retiendra pas.
    _version++;
    _miroirAccess = null;
    _accessDejaVu = false;
    _accessEnCours = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
  }
}
