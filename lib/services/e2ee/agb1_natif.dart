import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Le format AGB1 chiffré PAR LE PROCESSEUR (Android, `ChiffrementAgb1.kt`).
///
/// 🐛 « UNE PETITE LENTEUR, MÊME MÉDIAS CHIFFRÉS EN COURS » (patron,
/// 18/10/2026) : le chiffrement des médias tournait en Dart pur
/// (`pointycastle`), sans les instructions AES du processeur. Android les a
/// (javax.crypto) : mêmes octets, bien plus vite.
///
/// ⚠️ TOUJOURS UN REPLI : `null` veut dire « pas de natif ici » (web, iOS,
/// tests, ancien code natif) — l'appelant chiffre alors en Dart comme avant.
/// Une erreur du natif n'est JAMAIS une erreur pour l'utilisateur : elle fait
/// basculer sur le chemin Dart, une seule fois pour toute la session.
class Agb1Natif {
  Agb1Natif._();

  static const _canal = MethodChannel('alanya/chiffrement');
  static bool _horsService = false;
  static int _jeton = 0;
  static final Map<int, void Function(double)> _progressions = {};
  static bool _ecoute = false;

  static bool get disponible =>
      !_horsService && !kIsWeb && Platform.isAndroid;

  static void _ecouter() {
    if (_ecoute) return;
    _ecoute = true;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method != 'progression') return;
      final a = appel.arguments;
      if (a is! Map) return;
      final f = _progressions[a['jeton']];
      final v = a['fraction'];
      if (f != null && v is num) f(v.toDouble());
    });
  }

  /// Chiffre [source] (un chemin) ou [octets] vers [destination] avec [cle].
  /// Rend `(taille, tailleClair, empreinte)`, ou `null` : à faire en Dart.
  static Future<({int taille, int tailleClair, Uint8List empreinte})?>
      chiffrerFichier({
    required String destination,
    required Uint8List cle,
    String? source,
    Uint8List? octets,
    void Function(double fraction)? onProgression,
  }) async {
    if (!disponible) return null;
    _ecouter();
    final jeton = ++_jeton;
    if (onProgression != null) _progressions[jeton] = onProgression;
    try {
      final r = await _canal.invokeMapMethod<String, Object?>('chiffrerFichier', {
        'source': source,
        'octets': octets,
        'destination': destination,
        'cle': cle,
        'jeton': jeton,
      });
      if (r == null) return null;
      return (
        taille: (r['taille'] as num).toInt(),
        tailleClair: (r['tailleClair'] as num).toInt(),
        empreinte: r['empreinte'] as Uint8List,
      );
    } on MissingPluginException {
      _horsService = true;
      return null;
    } catch (e) {
      debugPrint('[Agb1Natif] chiffrement natif impossible, repli Dart : $e');
      _horsService = true;
      return null;
    } finally {
      _progressions.remove(jeton);
    }
  }

  /// Vérifie l'empreinte puis déchiffre. `null` : à faire en Dart.
  /// Lève [StateError] avec le message du natif si le FICHIER est invalide —
  /// l'appelant le traduit en `FichierInvalide`.
  static Future<Uint8List?> dechiffrer(
    Uint8List chiffre, {
    required Uint8List cle,
    required String empreinte,
    required int taille,
  }) async {
    if (!disponible) return null;
    try {
      return await _canal.invokeMethod<Uint8List>('dechiffrer', {
        'chiffre': chiffre,
        'cle': cle,
        'empreinte': empreinte,
        'taille': taille,
      });
    } on PlatformException catch (e) {
      if (e.code == 'INVALIDE') throw StateError(e.message ?? 'fichier invalide');
      debugPrint('[Agb1Natif] déchiffrement natif impossible, repli Dart : $e');
      _horsService = true;
      return null;
    } on MissingPluginException {
      _horsService = true;
      return null;
    }
  }
}
