import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';

/// LES NOMS QUE J'AI DONNÉS À MES CONTACTS, appliqués PARTOUT.
///
/// 🔴 DEMANDE DU PATRON (18/10/2026) : « ce nom-là, quand tu m'écris, c'est ce
/// nom-là qui doit s'afficher. Quand tu m'appelles, c'est ce nom-là. » Le nom
/// donné dans la fiche d'un contact (`Contact.alias`) ne servait jusqu'ici
/// qu'à l'écran des contacts.
///
/// Règle unique, comme l'application Talky de l'équipe (`ContactAliases`) :
/// le nom que J'AI donné s'il existe, sinon le nom du profil. Elle vaut pour
/// les titres des discussions, les noms dans les groupes, les appels, les
/// statuts et les notifications construites par l'application. Le serveur
/// applique la même règle aux notifications qu'il envoie (`push.mjs`).
///
/// ⚠️ CE QUI SORT DE L'APPLICATION GARDE LE NOM DU PROFIL : une mention écrite,
/// un contact partagé, ce qu'on envoie au serveur. Le nom donné est privé.
///
/// ⚠️ UN COMPTE QUI REFUSE D'ÊTRE RENOMMÉ : le serveur ne renvoie pas son nom
/// donné (`alias: null`), il n'entre donc jamais ici.
///
/// Gardé sur le téléphone : il sert dès le premier affichage, avant que la
/// liste des contacts n'arrive. Vidé à la déconnexion.
class NomsDonnes {
  NomsDonnes._();

  static const _cle = 'noms_donnes';
  static final Map<String, String> _noms = {};

  /// Change à chaque mise à jour : les écrans ouverts peuvent l'écouter.
  static final ValueNotifier<int> version = ValueNotifier(0);

  /// Le nom donné à [userId], ou `null`.
  static String? de(String? userId) => userId == null ? null : _noms[userId];

  /// Le nom à afficher pour [userId] : le nom donné, sinon [nomDuProfil].
  static String nomPour(String? userId, String nomDuProfil) =>
      de(userId) ?? nomDuProfil;

  /// Relit la copie du téléphone — au démarrage, avant le premier écran.
  static Future<void> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      final brut = p.getString(_cle);
      if (brut == null) return;
      final m = jsonDecode(brut);
      if (m is! Map) return;
      _noms
        ..clear()
        ..addAll({
          for (final e in m.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
        });
      version.value++;
    } catch (_) {
      // Copie illisible : les noms reviendront avec la liste des contacts.
    }
  }

  /// La liste des contacts vient d'arriver du serveur : elle fait foi.
  static Future<void> depuisContacts(List<Contact> contacts) async {
    final nouveaux = <String, String>{
      for (final c in contacts)
        if ((c.alias ?? '').trim().isNotEmpty) c.userId: c.alias!.trim(),
    };
    if (mapEquals(nouveaux, _noms)) return;
    _noms
      ..clear()
      ..addAll(nouveaux);
    await _garder();
  }

  /// Un nom vient d'être donné (ou retiré, si [nom] est vide) dans la fiche.
  static Future<void> poser(String userId, String? nom) async {
    final n = nom?.trim() ?? '';
    if (n.isEmpty) {
      if (_noms.remove(userId) == null) return;
    } else {
      if (_noms[userId] == n) return;
      _noms[userId] = n;
    }
    await _garder();
  }

  /// Déconnexion : le compte suivant ne doit rien voir du précédent.
  static Future<void> vider() async {
    _noms.clear();
    version.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_cle);
    } catch (_) {}
  }

  static Future<void> _garder() async {
    version.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cle, jsonEncode(_noms));
    } catch (_) {}
  }

  /// Pour les tests : un registre connu, sans téléphone.
  @visibleForTesting
  static void poserPourTest(Map<String, String> noms) {
    _noms
      ..clear()
      ..addAll(noms);
  }
}
