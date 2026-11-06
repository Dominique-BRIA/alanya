import 'package:flutter/material.dart';

import '../../core/in_app_notifier.dart';
import '../../core/push_service.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// L'appel qui sonne, en PETIT : le bandeau d'appel entrant (Refuser /
/// Répondre) en haut de l'application (06/11/2026).
///
/// C'est la forme réduite de l'écran de sonnerie, comme le bandeau d'un appel
/// en cours est celle de l'écran d'appel. On y arrive par la flèche « Réduire »
/// ou par le bouton retour ; toucher le bandeau rouvre l'écran plein.
///
/// [cc] est passé en paramètre, jamais relu depuis un contexte : l'écran qui
/// appelle cette fonction est en train de se fermer.
void afficherAppelEntrantReduit(CallController cc) {
  final inc = cc.incoming;
  if (inc == null) return;
  cc.entrantReduit = inc.callId;
  InAppNotifier.instance.showCall(
    title: inc.displayTitle,
    avatarUrl: inc.callerAvatarUrl,
    isVideo: inc.callType == "VIDEO",
    onTap: () {
      InAppNotifier.instance.dismissCall();
      ouvrirEcranSonnerie(cc);
    },
    onAccept: () async {
      await cc.acceptIncoming();
      await ouvrirEcranSonnerie(cc);
    },
    onReject: () {
      cc.rejectIncoming();
    },
  );
}

/// Ouvre l'écran de sonnerie en grand, par le navigateur GLOBAL.
///
/// Rien n'est empilé si l'écran est déjà là : deux écrans d'appel l'un sur
/// l'autre demandaient deux retours pour en sortir. Au démarrage à froid, le
/// navigateur peut n'être pas encore construit : on lui laisse une seconde.
Future<void> ouvrirEcranSonnerie(CallController cc) async {
  cc.entrantReduit = null;
  for (var essai = 0; essai < 10; essai++) {
    if (cc.callScreenVisible) return;
    final nav = PushService.navigatorKey.currentState;
    if (nav != null) {
      nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ActiveCallScreen(incoming: true),
      ));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
