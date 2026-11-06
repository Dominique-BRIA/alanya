import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Les refus d'appel qui n'ont pas pu partir (06/11/2026).
///
/// Refuser sans réseau — ascenseur, sous-sol, données coupées — perdait le
/// refus : l'appel disparaissait de l'écran, mais le serveur n'en savait rien
/// et l'appelant sonnait jusqu'à l'expiration, persuadé qu'on ne décrochait
/// pas. Le refus est désormais GARDÉ, puis renvoyé : quelques tentatives
/// rapprochées tant que l'appel peut encore sonner, puis au prochain
/// démarrage de l'application.
///
/// ⚠️ UN REFUS N'A DE SENS QUE PENDANT LA SONNERIE. Passé deux minutes,
/// l'appel est clos de toute façon (le serveur l'abandonne à 90 s) : le
/// renvoyer ne servirait à rien, on l'oublie.
///
/// L'ENVOI EST FOURNI PAR L'APPELANT. L'application passe par son client
/// d'API, qui sait renouveler la session ; l'isolate du push, qui n'a pas ce
/// client, passe par une requête directe. Les deux partagent la file.
class RefusEnAttente {
  RefusEnAttente._();

  static const _cle = 'refus_appels_en_attente';
  static const _dureeDeVie = Duration(minutes: 2);
  static const _delais = [
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 25),
    Duration(seconds: 35),
  ];

  /// Résultat d'une tentative d'envoi.
  /// - [envoye] : le serveur a répondu — refus enregistré, ou appel déjà clos.
  /// - [aRefaire] : pas de réseau, ou serveur en panne : on réessaiera.
  static const envoye = true;
  static const aRefaire = false;

  /// Refuse [callId] avec [envoyer] ; en cas d'échec, garde le refus et
  /// réessaie tant que l'appel peut encore sonner.
  static Future<void> refuser(
    String callId,
    Future<bool> Function(String callId) envoyer,
  ) async {
    if (await _essayer(callId, envoyer)) {
      // Le natif a pu le mettre en file de son côté : il ne le renverra pas.
      await _retirer(callId);
      return;
    }
    await _ajouter(callId);
    await _reessayer(callId, envoyer);
  }

  /// Reprend un refus que le NATIF a mis en file (`RefusNatif.kt`) sans
  /// parvenir à l'envoyer — jeton d'accès expiré, typiquement, que seul
  /// Flutter sait renouveler. Sans effet si le refus est déjà parti.
  static Future<void> reprendre(
    String callId,
    Future<bool> Function(String callId) envoyer,
  ) async {
    if (!await _toujoursEnAttente(callId)) return;
    if (await _essayer(callId, envoyer)) {
      await _retirer(callId);
      return;
    }
    await _reessayer(callId, envoyer);
  }

  static Future<void> _reessayer(
    String callId,
    Future<bool> Function(String callId) envoyer,
  ) async {
    for (final delai in _delais) {
      await Future<void>.delayed(delai);
      if (!await _toujoursEnAttente(callId)) return;
      if (await _essayer(callId, envoyer)) {
        await _retirer(callId);
        return;
      }
    }
  }

  /// Renvoie les refus encore utiles, oublie les périmés. Appelé au démarrage
  /// de l'application et à son retour au premier plan.
  static Future<void> rejouer(
      Future<bool> Function(String callId) envoyer) async {
    final file = await _lire();
    if (file.isEmpty) return;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    for (final entree in file.entries) {
      final age = Duration(milliseconds: maintenant - entree.value);
      if (age > _dureeDeVie || await _essayer(entree.key, envoyer)) {
        await _retirer(entree.key);
      }
    }
  }

  static Future<bool> _essayer(
      String callId, Future<bool> Function(String callId) envoyer) async {
    try {
      return await envoyer(callId);
    } on SocketException {
      return aRefaire;
    } on TimeoutException {
      return aRefaire;
    } on HttpException {
      return aRefaire;
    } catch (_) {
      return aRefaire;
    }
  }

  static Future<Map<String, int>> _lire() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final brut = p.getString(_cle);
      if (brut == null || brut.isEmpty) return {};
      return (jsonDecode(brut) as Map).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _ecrire(Map<String, int> file) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (file.isEmpty) {
        await p.remove(_cle);
      } else {
        await p.setString(_cle, jsonEncode(file));
      }
    } catch (_) {}
  }

  static Future<void> _ajouter(String callId) async {
    final file = await _lire();
    file.putIfAbsent(callId, () => DateTime.now().millisecondsSinceEpoch);
    await _ecrire(file);
  }

  static Future<void> _retirer(String callId) async {
    final file = await _lire();
    if (file.remove(callId) != null) await _ecrire(file);
  }

  /// Un autre isolate a pu l'envoyer entre-temps : on ne le renvoie pas.
  static Future<bool> _toujoursEnAttente(String callId) async =>
      (await _lire()).containsKey(callId);
}
