import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'call_controller.dart';
import 'screens/active_call_screen.dart';

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
