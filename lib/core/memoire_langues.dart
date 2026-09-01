import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// LA LANGUE DE CHAQUE CORRESPONDANT, apprise au fil des messages.
///
/// 🔴 LE VRAI LEVIER CONTRE LES FAUSSES DÉTECTIONS. Un message de trois mots
/// est indécidable : « merci » est français, portugais et proche de l'italien.
/// Son AUTEUR, lui, écrit presque toujours dans la même langue. On cesse donc
/// de deviner message par message pour se souvenir de la personne.
///
/// ⚠️ ON N'APPREND QUE DES DÉTECTIONS SÛRES — texte assez long, confiance
/// haute. Apprendre d'une détection douteuse figerait l'erreur : toutes les
/// suivantes s'appuieraient dessus, et le défaut deviendrait permanent au lieu
/// d'être passager. Mieux vaut ne rien savoir que savoir faux.
///
/// ⚠️ CETTE MÉMOIRE EST UN INDICE, PAS UNE VÉRITÉ. Elle sert quand la détection
/// n'ose pas se prononcer ; une détection sûre la contredit et la remplace —
/// quelqu'un peut changer de langue, et c'est même courant dans un groupe.
///
/// Purement locale, jamais envoyée nulle part : c'est une observation faite sur
/// cet appareil, pas une donnée du compte.
class MemoireLangues {
  MemoireLangues._();

  static const _cle = "langues_correspondants";

  /// Les langues FIXÉES à la main, par correspondant.
  ///
  /// 🔴 ELLES PRIMENT SUR TOUT — sur la détection comme sur ce qui a été
  /// appris (demande du user, 31/08/2026). Quelqu'un qui sait dans quelle
  /// langue son interlocuteur écrit en sait toujours plus que ML Kit sur trois
  /// mots ; lui demander de le dire une fois vaut mieux que le deviner cent
  /// fois.
  ///
  /// Absence d'entrée = « auto », c'est-à-dire le mécanisme de détection.
  /// C'est le défaut, et il ne se stocke pas : ne rien écrire est déjà dire
  /// « devine ».
  static const _cleFixees = "langues_fixees";

  static Map<String, String>? _cacheFixees;

  /// Plafond d'entrées retenues.
  ///
  /// Sans lui, la carte grandirait indéfiniment dans les préférences — et
  /// personne n'écrit à mille personnes. Au-delà, on repart de zéro plutôt que
  /// d'inventer une politique d'éviction : la mémoire se reconstitue seule au
  /// fil des messages suivants, et perdre cet indice ne coûte qu'une détection.
  static const int _plafond = 500;

  static Map<String, String>? _cache;

  static Future<Map<String, String>> _charge() async {
    final connu = _cache;
    if (connu != null) return connu;
    try {
      final prefs = await SharedPreferences.getInstance();
      final brut = prefs.getString(_cle);
      if (brut == null || brut.isEmpty) return _cache = {};
      final decode = jsonDecode(brut);
      if (decode is! Map) return _cache = {};
      return _cache = {
        for (final e in decode.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      // Préférences illisibles : on repart d'une mémoire vide. Elle n'est
      // qu'un indice, son absence ne casse rien.
      return _cache = {};
    }
  }

  static Future<Map<String, String>> _chargeFixees() async {
    final connu = _cacheFixees;
    if (connu != null) return connu;
    try {
      final prefs = await SharedPreferences.getInstance();
      final brut = prefs.getString(_cleFixees);
      if (brut == null || brut.isEmpty) return _cacheFixees = {};
      final decode = jsonDecode(brut);
      if (decode is! Map) return _cacheFixees = {};
      return _cacheFixees = {
        for (final e in decode.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return _cacheFixees = {};
    }
  }

  /// La langue FIXÉE pour [userId], ou `null` si elle est en « auto ».
  static Future<String?> langueFixee(String userId) async {
    if (userId.isEmpty) return null;
    final carte = await _chargeFixees();
    return carte[userId];
  }

  /// Fixe la langue de [userId], ou revient à « auto » avec `null`.
  ///
  /// ⚠️ REVENIR À « AUTO » N'EFFACE PAS CE QUI A ÉTÉ APPRIS : les deux mémoires
  /// sont distinctes. C'est voulu — celui qui relâche la consigne retrouve la
  /// meilleure observation disponible, pas une page blanche.
  static Future<void> fixe(String userId, String? langue) async {
    if (userId.isEmpty) return;
    final carte = await _chargeFixees();
    if (langue == null || langue.isEmpty) {
      if (!carte.containsKey(userId)) return;
      carte.remove(userId);
    } else {
      if (carte[userId] == langue) return;
      carte[userId] = langue;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleFixees, jsonEncode(carte));
    } catch (_) {}
  }

  /// La langue connue de [userId], ou `null`.
  ///
  /// ⚠️ LA LANGUE FIXÉE PRIME sur celle qui a été apprise. Un appelant qui
  /// n'interrogerait que la mémoire d'observation ignorerait la consigne
  /// explicite de l'utilisateur — c'est ici, et pas chez l'appelant, que
  /// l'ordre des deux se décide.
  static Future<String?> langueDe(String userId) async {
    if (userId.isEmpty) return null;
    final fixee = await langueFixee(userId);
    if (fixee != null && fixee.isNotEmpty) return fixee;
    final carte = await _charge();
    return carte[userId];
  }

  /// Version synchrone, pour un appel dans un chemin qui ne peut pas attendre.
  ///
  /// Rend `null` tant que [langueDe] n'a pas été appelée au moins une fois :
  /// c'est un raccourci, pas une source à part.
  static String? langueDeSync(String userId) => _cache?[userId];

  /// Retient que [userId] écrit en [langue] — appel réservé aux détections
  /// SÛRES.
  static Future<void> retiens(String userId, String langue) async {
    if (userId.isEmpty || langue.isEmpty) return;
    // Une langue fixée à la main n'a pas à être « corrigée » par une
    // observation : l'utilisateur a tranché, et une détection sûre sur un
    // message isolé ne le contredit pas.
    if (await langueFixee(userId) != null) return;
    final carte = await _charge();
    if (carte[userId] == langue) return;
    if (carte.length >= _plafond && !carte.containsKey(userId)) carte.clear();
    carte[userId] = langue;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cle, jsonEncode(carte));
    } catch (_) {
      // L'écriture a échoué : la mémoire vit encore en RAM pour cette session.
    }
  }

  /// Vide la mémoire — à la déconnexion, avec les autres caches du compte.
  ///
  /// ⚠️ Sans cela, les langues observées sur un compte serviraient d'indice au
  /// compte suivant sur le même téléphone.
  static Future<void> clear() async {
    _cache = {};
    _cacheFixees = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cle);
      // Les langues fixées partent aussi : elles désignent des correspondants
      // du compte qu'on quitte.
      await prefs.remove(_cleFixees);
    } catch (_) {}
  }
}
