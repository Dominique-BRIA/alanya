import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// LES DERNIÈRES RÉPONSES DU SERVEUR, gardées pour un affichage IMMÉDIAT.
///
/// 🐛 « TOUT EST CHARGÉ INDÉFINIMENT » (user, 10/10/2026). Réunions, profil,
/// fiches : chaque ouverture attendait le réseau, avec une roue qui tourne —
/// sur une connexion lente, longtemps. Un écran montre maintenant ce qu'il a
/// reçu la dernière fois, puis se met à jour quand le serveur répond.
///
/// ⚠️ DU JSON BRUT, tel que le serveur l'a rendu : on le relit avec le même
/// `fromJson`, sans second format à maintenir.
///
/// ⚠️ VIDÉ À LA DÉCONNEXION (`AuthController.logout`) : le compte suivant sur
/// ce téléphone ne doit rien voir du précédent.
class CacheEcrans {
  static const _prefixe = 'cache_ecran.';

  static Future<Object?> lire(String cle) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('$_prefixe$cle');
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> ecrire(String cle, Object? valeur) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefixe$cle', jsonEncode(valeur));
    } catch (_) {
      // Sans cache, l'écran attendra le réseau, comme avant.
    }
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_prefixe)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
