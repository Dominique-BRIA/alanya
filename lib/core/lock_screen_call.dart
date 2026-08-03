import 'dart:io';

import 'package:flutter/services.dart';

/// Affichage de l'écran d'appel par-dessus l'écran verrouillé.
///
/// Passe par le canal natif déclaré dans `MainActivity.kt`. Le comportement
/// n'est allumé QUE le temps d'un appel entrant, jamais en permanence : posé
/// dans le manifeste, il rendrait toute l'application accessible sans
/// déverrouiller — conversations, médias et réglages compris.
///
/// Ne fait rien hors Android : ni iOS ni le bureau n'ont cette notion, et le
/// canal n'y est pas déclaré.
class LockScreenCall {
  LockScreenCall._();

  static const _canal = MethodChannel('alanya/ecran_verrouille');
  static bool _actif = false;

  /// Autorise l'application à s'afficher par-dessus le verrouillage et à
  /// allumer l'écran. À appeler quand un appel entrant se présente.
  static Future<void> activer() => _regler(true);

  /// Rend la main au verrouillage. À appeler dès que l'appel est terminé,
  /// refusé, ou que l'écran d'appel se ferme.
  static Future<void> desactiver() => _regler(false);

  static Future<void> _regler(bool actif) async {
    if (!Platform.isAndroid) return;
    // L'état est suivi ici pour ne pas traverser le pont natif à chaque
    // reconstruction de widget : `activer()` est appelé depuis un `build`
    // indirect, il peut l'être plusieurs fois de suite.
    if (_actif == actif) return;
    _actif = actif;
    try {
      await _canal.invokeMethod('afficherParDessusVerrouillage', {'actif': actif});
    } catch (_) {
      // Canal absent (vieille version installée par-dessus, ou plateforme sans
      // implémentation) : l'appel s'affichera simplement une fois déverrouillé,
      // comme avant. Rien ne doit échouer pour autant.
      _actif = !actif;
    }
  }
}
