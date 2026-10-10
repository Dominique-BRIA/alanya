import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/push_service.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// Ouvre l'écran d'un appel qu'on vient de LANCER, sans dépendre du widget qui
/// l'a lancé.
///
/// 🔴 CETTE FONCTION EXISTE À CAUSE D'UNE PANNE INTERMITTENTE : « parfois
/// l'écran d'appel ne s'ouvre pas ». Les sept écrans qui lancent un appel
/// faisaient tous la même chose :
///
/// ```dart
/// await cc.startOutgoing(...);
/// if (!mounted) return;          // ← ABANDON SILENCIEUX
/// Navigator.of(context).push(... ActiveCallScreen ...);
/// ```
///
/// Or `startOutgoing` est précédé d'un `createDirect` : DEUX allers-retours
/// réseau. Si le widget appelant disparaît pendant ce temps, le `!mounted`
/// renvoie — et l'appel, lui, EST bel et bien parti. Le correspondant sonne,
/// l'appelant ne voit rien, et seul le bandeau global le trahit.
///
/// ⚠️ CE N'EST PAS UN CAS DE BORD SUR LES LISTES. Un appel lancé depuis une
/// tuile de collègue ou une carte de centre s'expose le plus : ces tuiles se
/// démontent dès que la liste qui les contient se reconstruit, ce qu'un
/// événement WebSocket suffit à provoquer. D'où le « parfois ».
///
/// La parade est de ne PLUS passer par le `Navigator` du widget appelant, mais
/// par le navigateur GLOBAL, qui survit à sa disparition.
///
/// ⚠️ [cc] EST PASSÉ EN PARAMÈTRE, jamais relu depuis un `BuildContext` : le
/// contexte d'appel peut justement être mort. Les appelants le saisissent avant
/// leurs `await`, ce que la plupart faisaient déjà.
Future<void> ouvrirEcranAppelLance(CallController cc) async {
  // L'appel n'a pas démarré (exception attrapée plus haut) : rien à montrer.
  if (cc.activeCallId == null) return;
  // Déjà à l'écran — en empiler un second obligerait à deux retours pour en
  // sortir. Même garde-fou que `_rouvrirEcranAppel` dans `CallListener`.
  if (cc.callScreenVisible) return;

  // Même boucle d'attente que l'ouverture d'un appel ENTRANT : au démarrage à
  // froid, le navigateur global peut n'être pas encore construit.
  for (var essai = 0; essai < 10; essai++) {
    final nav = PushService.navigatorKey.currentState;
    if (nav != null) {
      await nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ActiveCallScreen(),
      ));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // Navigateur introuvable : l'appel reste actif et le bandeau global permet
  // d'y revenir. Mieux vaut ça qu'une exception qui coupe tout.
  debugPrint("[appel] navigateur global indisponible, écran non ouvert");
}

/// Ouvre l'écran d'appel si [callId] désigne l'appel auquel CET appareil
/// participe. Renvoie vrai quand l'écran a été ouvert, pour que l'appelant
/// puisse abandonner sa propre action.
///
/// Sert aux deux listes où un appel apparaît comme « En cours » : la liste des
/// appels et celle des discussions. Sans ça, appuyer sur un appel en cours
/// ouvrait la conversation — l'appel continuait derrière, sans aucun moyen de
/// revenir à son écran autrement que par le bandeau global.
///
/// ⚠️ La condition porte sur `activeCallId`, et pas sur le STATUT de l'appel.
/// Un appel peut être « ONGOING » sans nous concerner — entre deux autres
/// personnes d'un groupe, ou parce que nous l'avons quitté sans qu'il se
/// termine. Ouvrir l'écran d'appel dans ces cas afficherait une page vide.
/// Seul `activeCallId` dit que c'est bien NOTRE appel, sur CET appareil.
bool ouvrirSiAppelEnCours(BuildContext context, String? callId) {
  if (callId == null) return false;
  if (context.read<CallController>().activeCallId != callId) return false;

  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const ActiveCallScreen(),
    ),
  );
  return true;
}
