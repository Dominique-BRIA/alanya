import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé des tokens JWT (Keychain iOS / Keystore Android).
/// Persiste après fermeture / redémarrage de l'app.
///
/// ═══════════════════════════════════════════════════════════════════════
/// 🔴 CE FICHIER A EMPÊCHÉ DES GENS DE SE RECONNECTER. Ce qui s'affichait :
///
///   PlatformException(Exception encountered,
///   Migration failed after algorithm change (Invalid key, key...))
///
/// Trois décisions, chacune raisonnable seule, se combinaient en impasse.
/// ═══════════════════════════════════════════════════════════════════════
class TokenStorage {
  /*
   * ① `encryptedSharedPreferences: true` EST RETIRÉ.
   *
   * En version 10 du greffon, ce paramètre est DÉPRÉCIÉ ET IGNORÉ : la
   * bibliothèque Jetpack Security de Google est abandonnée. Mais le passer
   * n'est pas neutre pour autant — il désigne les données comme héritées et
   * déclenche leur MIGRATION vers les chiffrements internes du greffon.
   *
   * ⚠️ C'EST CETTE MIGRATION QUI ÉCHOUAIT. L'ancienne clé maîtresse ne se
   * déballait plus (« Invalid key »), et la migration lève au lieu de passer
   * son chemin.
   *
   * ② `resetOnError` REVIENT À SA VALEUR NORMALE, `true`.
   *
   * Il était à `false` avec ce commentaire : « ne jamais effacer
   * silencieusement en cas d'erreur de déchiffrement ». L'intention est
   * bonne, et pour une clé de chiffrement elle serait juste.
   *
   * ⚠️ MAIS CE COFFRE-CI NE CONTIENT QUE DU JETABLE : deux jetons et un
   * profil en cache. Les perdre coûte UNE reconnexion. Refuser de les
   * effacer coûtait L'ACCÈS AU COMPTE, définitivement — plus aucune
   * connexion ne pouvait aboutir, et rien dans l'application ne permettait
   * d'en sortir.
   *
   * 🔴 LA RÈGLE : on ne protège de l'effacement que ce qu'on ne peut pas
   * refabriquer. Un jeton se refabrique en tapant son mot de passe.
   *
   * ③ UN ESPACE DE NOM À PART, ET C'EST CE QUI REND ② SANS DANGER.
   *
   * ⚠️ SANS LUI, LA REMISE À ZÉRO EMPORTERAIT LES CLÉS SIGNAL. `CoffreE2ee`
   * écrit dans le MÊME coffre : l'identité de l'appareil, les pré-clés, la
   * clé maîtresse de l'archive. Un effacement déclenché par un jeton illisible
   * détruirait tout cela — et là, rien ne se refabrique : les messages reçus
   * deviendraient indéchiffrables.
   *
   * L'espace de nom sépare aussi les alias du Keystore, pas seulement les
   * fichiers. Les deux coffres ne peuvent plus se marcher dessus.
   *
   * ⚠️ PRIX À PAYER, ASSUMÉ : les jetons déjà en place vivent sous l'ancien
   * espace de nom et deviennent invisibles. Tout le monde se reconnecte UNE
   * fois. C'est déjà ce qui se passe aujourd'hui, à la différence près que
   * cette fois la reconnexion aboutit.
   */
  static const _android = AndroidOptions(
    storageNamespace: 'alanya_session',
    resetOnError: true,
  );
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: false,
  );
  static const _storage = FlutterSecureStorage(
    aOptions: _android,
    iOptions: _ios,
  );

  static const _kAccess = "alanya_access_token";
  static const _kRefresh = "alanya_refresh_token";
  static const _kUser = "alanya_user_json";

  /// Lecture qui ne fait jamais échouer l'écran qui la demande.
  ///
  /// ⚠️ UN JETON ILLISIBLE N'EST PAS UNE PANNE, C'EST UNE ABSENCE DE SESSION.
  /// Laisser l'exception remonter transformait un coffre abîmé en application
  /// inutilisable ; rendre `null` mène simplement à l'écran de connexion,
  /// c'est-à-dire exactement là où il faut aller.
  static Future<String?> _lire(String cle) async {
    try {
      return await _storage.read(key: cle);
    } on PlatformException {
      return null;
    }
  }

  /// Écriture qui se soigne une fois avant d'abandonner.
  ///
  /// ⚠️ ON NE RÉESSAIE QU'UNE SEULE FOIS, et seulement après avoir vidé cet
  /// espace de nom. Boucler sur un coffre abîmé ne le réparerait pas ; et si
  /// la seconde tentative échoue encore, il faut que la connexion le DISE —
  /// `messageDErreur` nommera l'exception au lieu d'accuser le réseau.
  static Future<void> _ecrire(String cle, String valeur) async {
    try {
      await _storage.write(key: cle, value: valeur);
    } on PlatformException {
      await _storage.deleteAll();
      await _storage.write(key: cle, value: valeur);
    }
  }

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await _ecrire(_kAccess, access);
    await _ecrire(_kRefresh, refresh);
  }

  Future<String?> get accessToken => _lire(_kAccess);
  Future<String?> get refreshToken => _lire(_kRefresh);

  // --- Profil utilisateur en cache, pour un démarrage instantané offline ---
  Future<void> saveUserJson(String json) => _ecrire(_kUser, json);
  Future<String?> get userJson => _lire(_kUser);

  Future<void> clear() async {
    /*
     * ⚠️ `deleteAll` ET NON TROIS `delete` : depuis que cet espace de nom est
     * à nous seuls, il ne contient rien d'autre. Et une entrée devenue
     * illisible ne se supprime pas toujours par sa clé, alors qu'un
     * effacement d'ensemble, lui, part du principe qu'il n'y a rien à lire.
     */
    try {
      await _storage.deleteAll();
    } on PlatformException {
      // Déjà inutilisable : il n'y a plus rien à protéger.
    }
  }
}
