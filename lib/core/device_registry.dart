import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'token_storage.dart';

/// Registre des appareils du compte : ce qui alimente l'écran
/// « Appareils connectés ».
///
/// À ne pas confondre avec [PushService], qui n'enregistre qu'un jeton FCM pour
/// les notifications, sans état présentable à l'utilisateur.
///
/// Volontairement sans dépendance native : `dart:io` suffit à identifier
/// l'appareil, et ajouter un paquet comme `device_info_plus` fragiliserait le
/// build CI pour un libellé.
class DeviceRegistry {
  DeviceRegistry._();
  static final DeviceRegistry instance = DeviceRegistry._();

  ApiClient? _api;
  TokenStorage? _storage;

  /// Clé du même nom que côté web : le serveur reconnaît l'appareil par cet
  /// identifiant, quelle que soit la plateforme.
  static const _cleId = 'cookies_WebID';

  /// Identifiant de la LIGNE d'appareil, renvoyé par le serveur.
  ///
  /// À ne pas confondre avec `cookies_WebID`, qui identifie le téléphone : la
  /// ligne vaut pour un couple (téléphone, compte). C'est elle que le serveur
  /// désigne quand une conversation est réservée à un poste précis.
  static const _cleAppareilId = 'appareil_id';

  void init({required ApiClient api, required TokenStorage storage}) {
    _api = api;
    _storage = storage;
  }

  /// Identifiant stable de cet appareil, créé au premier appel puis conservé.
  ///
  /// Sans lui, chaque connexion créerait une ligne de plus dans le registre.
  /// Il ne survit pas à une désinstallation — l'appareil réapparaîtra alors
  /// comme neuf, ce qui est le comportement attendu.
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existant = prefs.getString(_cleId);
    if (existant != null && existant.isNotEmpty) return existant;

    final rnd = Random.secure();
    final id = List.generate(24, (_) => rnd.nextInt(36).toRadixString(36)).join();
    final complet = 'mob-$id';
    await prefs.setString(_cleId, complet);
    return complet;
  }

  /// Code attendu par le serveur : 0=web 1=Android 2=iOS 3=bureau.
  int get _typeDevice {
    if (Platform.isAndroid) return 1;
    if (Platform.isIOS) return 2;
    return 3;
  }

  /// Version courte du système, ex. « Android 13 ».
  String get _systeme {
    final brut = Platform.operatingSystemVersion;
    if (Platform.isAndroid) {
      final m = RegExp(r'Android\s+([\d.]+)').firstMatch(brut);
      return m != null ? 'Android ${m.group(1)}' : 'Android';
    }
    if (Platform.isIOS) {
      final m = RegExp(r'([\d.]+)').firstMatch(brut);
      return m != null ? 'iOS ${m.group(1)}' : 'iOS';
    }
    return Platform.operatingSystem;
  }

  /// Libellé lisible, deviné sans dépendance native.
  ///
  /// Sur Android, `operatingSystemVersion` contient l'empreinte de build, qui
  /// commence par la marque et le produit — « samsung/a54xnaxx/… ». On en tire
  /// un nom reconnaissable ; à défaut, un libellé générique que l'utilisateur
  /// pourra renommer.
  String get _libelle {
    if (Platform.isAndroid) {
      final apres = Platform.operatingSystemVersion.split(', ');
      if (apres.length > 1) {
        final morceaux = apres[1].split('/');
        if (morceaux.length >= 2) {
          final marque = morceaux[0].trim();
          final modele = morceaux[1].split(':').first.trim();
          if (marque.isNotEmpty && modele.isNotEmpty) {
            final m = marque[0].toUpperCase() + marque.substring(1);
            return '$m $modele';
          }
        }
      }
      return 'Téléphone Android';
    }
    if (Platform.isIOS) return 'iPhone';
    return 'Alanya';
  }

  /// Signale cet appareil au serveur. Idempotent : appelable à chaque
  /// démarrage, il met à jour la ligne existante au lieu d'en créer une autre.
  ///
  /// Échec silencieux : le registre est un confort, il ne doit jamais empêcher
  /// l'utilisateur d'entrer dans l'application.
  /// Identifiant de ligne du dernier enregistrement, ou null.
  ///
  /// Conservé pour survivre à un redémarrage : l'enregistrement ne repasse pas
  /// à chaque ouverture, et le temps réel doit pouvoir s'annoncer sans
  /// l'attendre.
  Future<int?> appareilId() async {
    final prefs = await SharedPreferences.getInstance();
    final valeur = prefs.getInt(_cleAppareilId);
    return (valeur != null && valeur > 0) ? valeur : null;
  }

  Future<void> registerIfAuthenticated() async {
    final api = _api, storage = _storage;
    if (api == null || storage == null) return;
    try {
      final token = await storage.accessToken;
      if (token == null) return;

      final reponse = await api.post(
        '/api/appareils',
        {
          'cookiesWebId': await deviceId(),
          'libelle': _libelle,
          'typeDevice': _typeDevice,
          'system': _systeme,
          'isOnline': 1,
        },
        bearer: token,
      );

      // On retient l'identifiant de ligne : sans lui, le serveur ne sait pas
      // quelle socket appartient à quel poste, et ne peut pas réserver une
      // conversation à un appareil précis.
      // `post` renvoie déjà une Map ; seul le contenu est incertain.
      final brut = reponse['appareil'];
      final id = (brut is Map) ? brut['appareilId'] : null;
      if (id is num && id > 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_cleAppareilId, id.toInt());
      }
      debugPrint('[DeviceRegistry] appareil enregistré');
    } catch (e) {
      debugPrint('[DeviceRegistry] enregistrement impossible : $e');
    }
  }

  /// Les appareils du compte, actifs d'abord. Lève en cas d'échec : l'écran
  /// qui l'appelle doit pouvoir afficher une erreur.
  Future<List<AppareilInfo>> list() async {
    final api = _api!, storage = _storage!;
    final token = await storage.accessToken;
    final data = await api.get('/api/appareils', bearer: token);
    final brut = (data['appareils'] as List?) ?? const [];
    return brut
        .map((e) => AppareilInfo.fromJson(e as Map<String, dynamic>))
        .where((a) => !a.revoked)
        .toList();
  }

  /// Déconnexion à distance d'un appareil.
  Future<void> disconnect(int appareilId) async {
    final api = _api!, storage = _storage!;
    final token = await storage.accessToken;
    await api.delete('/api/appareils/$appareilId', bearer: token);
  }

  /// Vrai si cet appareil est celui depuis lequel on navigue.
  Future<bool> isCurrent(AppareilInfo a) async =>
      a.cookiesWebId != null && a.cookiesWebId == await deviceId();
}

/// Un appareil tel que renvoyé par l'API.
class AppareilInfo {
  const AppareilInfo({
    required this.appareilId,
    required this.libelle,
    required this.typeDevice,
    required this.isOnline,
    required this.revoked,
    this.cookiesWebId,
    this.system,
    this.lastLogin,
  });

  final int appareilId;
  final String libelle;
  final int typeDevice;
  final bool isOnline;
  final bool revoked;
  final String? cookiesWebId;
  final String? system;
  final DateTime? lastLogin;

  factory AppareilInfo.fromJson(Map<String, dynamic> j) => AppareilInfo(
        appareilId: (j['appareilId'] as num).toInt(),
        libelle: j['libelle'] as String? ?? 'Appareil',
        typeDevice: (j['typeDevice'] as num?)?.toInt() ?? 0,
        isOnline: j['isOnline'] == true,
        revoked: j['revoked'] == true,
        cookiesWebId: j['cookiesWebId'] as String?,
        system: j['system'] as String?,
        lastLogin: j['lastLogin'] != null
            ? DateTime.tryParse(j['lastLogin'] as String)
            : null,
      );
}
