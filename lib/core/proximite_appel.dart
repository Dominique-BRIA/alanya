import 'dart:io';

import 'package:flutter/services.dart';

/// Extinction de l'écran quand le téléphone est porté à l'oreille.
///
/// ⚠️ CE N'EST PAS SEULEMENT UNE QUESTION D'ÉCRAN NOIR. Le verrou système
/// `PROXIMITY_SCREEN_OFF_WAKE_LOCK` coupe AUSSI la prise en compte du tactile
/// tant que le capteur est couvert. C'est lui, et lui seul, qui empêche la joue
/// ou l'oreille de raccrocher.
///
/// C'est pourquoi la solution spontanée — lire le capteur de proximité depuis
/// Flutter et masquer l'interface — ne marche pas : l'écran paraîtrait éteint,
/// mais les touches continueraient d'arriver, et le raccrochage accidentel
/// resterait entier. Il faut le verrou du système, pas son imitation.
///
/// Ne fait rien hors Android : ni iOS ni le bureau n'ont cette notion (iOS gère
/// la proximité tout seul pendant un appel), et le canal n'y est pas déclaré.
class ProximiteAppel {
  ProximiteAppel._();

  /// Le même canal que [LockScreenCall] : les deux réglages sont portés par
  /// `MainActivity`, il n'y a aucune raison d'en ouvrir un second.
  static const _canal = MethodChannel('alanya/ecran_verrouille');

  static bool _actif = false;

  /// Tient ou relâche le verrou.
  ///
  /// L'état est suivi ici pour ne pas traverser le pont natif à chaque
  /// reconstruction de widget : les appels viennent de `notifyListeners`, donc
  /// plusieurs fois de suite avec la même valeur.
  static Future<void> regler(bool actif) async {
    if (!Platform.isAndroid) return;
    if (_actif == actif) return;
    _actif = actif;
    try {
      await _canal.invokeMethod('capteurProximite', {'actif': actif});
    } catch (_) {
      // Canal absent (ancienne version installée par-dessus) ou appareil sans
      // capteur : l'écran restera simplement allumé, comme avant. Rien ne doit
      // échouer pour autant.
      _actif = !actif;
    }
  }
}
