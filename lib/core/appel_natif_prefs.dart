import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_config.dart';

/// Les appels TERMINÉS, connus de tous les isolates (06/11/2026).
///
/// Une annulation (`call_cancelled`) peut précéder l'appel qu'elle annule :
/// deux pushes ne garantissent pas leur ordre d'arrivée, et un téléphone qui
/// retrouve le réseau les reçoit en rafale. Sans cette liste, l'appel annulé
/// arrivé en second faisait sonner un plein écran pour un appel que plus
/// personne ne passait. Même rôle que `EndedCallRegistry` dans l'application
/// de référence.
///
/// Gardé dix minutes : au-delà, l'appel est de toute façon périmé (voir le
/// contrôle `sentAt` du push).
class AppelsTermines {
  AppelsTermines._();

  static const _cle = 'appels_termines';
  static const _duree = Duration(minutes: 10);

  static Future<void> marquer(String? callId) async {
    if (callId == null || callId.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final liste = _lire(p);
      liste[callId] = DateTime.now().millisecondsSinceEpoch;
      await p.setString(_cle, jsonEncode(liste));
    } catch (_) {}
  }

  static Future<bool> contient(String? callId) async {
    if (callId == null || callId.isEmpty) return false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return _lire(p).containsKey(callId);
    } catch (_) {
      return false;
    }
  }

  static Map<String, int> _lire(SharedPreferences p) {
    final brut = p.getString(_cle);
    if (brut == null || brut.isEmpty) return {};
    try {
      final limite =
          DateTime.now().millisecondsSinceEpoch - _duree.inMilliseconds;
      final liste = (jsonDecode(brut) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      liste.removeWhere((_, t) => t < limite);
      return liste;
    } catch (_) {
      return {};
    }
  }
}

/// Ce que le NATIF doit pouvoir lire sans Flutter (06/11/2026).
///
/// L'écran d'appel natif et le refus natif (`RefusNatif.kt`) agissent
/// application fermée : ils ne peuvent ni lire le stockage chiffré des jetons,
/// ni démarrer Flutter pour le demander. L'application leur recopie donc,
/// dans ses préférences privées, le JETON D'ACCÈS (courte durée) et l'adresse
/// de l'API — même principe que l'application de référence.
///
/// ⚠️ JAMAIS LE JETON DE RENOUVELLEMENT : il donne une session longue, et
/// notre serveur le remplace à chaque usage — le natif qui le consommerait
/// déconnecterait l'application. Un jeton d'accès expiré laisse simplement
/// le refus en file pour Flutter.
class PontNatifAppel {
  PontNatifAppel._();

  static Future<void> publierJeton(String? acces) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (acces == null || acces.isEmpty) {
        await p.remove('jeton_acces_natif');
      } else {
        await p.setString('jeton_acces_natif', acces);
      }
      await p.setString('api_base_natif', ServerConfig.apiBase);
    } catch (_) {}
  }

  /// Les libellés de l'écran natif, dans la langue choisie dans l'application.
  static Future<void> publierLibelles(Map<String, String> libelles) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('libelles_appel_natif', jsonEncode(libelles));
    } catch (_) {}
  }
}
