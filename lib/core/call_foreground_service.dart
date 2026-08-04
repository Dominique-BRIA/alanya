import 'dart:io';

import 'package:flutter/services.dart';

/// Service Android qui maintient l'appel vivant hors du premier plan.
///
/// Une fois l'appel établi, ce n'est plus Firebase qui le porte : c'est le
/// processus Flutter et ses connexions WebRTC. Or Android suspend les processus
/// en arrière-plan — écran éteint, changement d'application — et l'audio se
/// coupe alors au bout de quelques secondes.
///
/// Le service natif déclare au système que ce processus fait quelque chose que
/// l'utilisateur a demandé, et prend les verrous CPU et Wi-Fi. Voir
/// `CallForegroundService.kt` pour le détail.
///
/// ⚠️ La VIDÉO reste interrompue écran éteint : Android interdit l'accès caméra
/// en arrière-plan quel que soit le service. L'audio continue, l'image se fige.
class CallForegroundService {
  CallForegroundService._();

  static const _canal = MethodChannel('alanya/ecran_verrouille');
  static bool _actif = false;

  /// À appeler quand l'appel devient ACTIF — pas quand il sonne. Un appel qui
  /// sonne n'a pas encore de flux à protéger, et la notification persistante
  /// ferait double emploi avec celle de l'appel entrant.
  static Future<void> demarrer({String titre = "Appel en cours"}) =>
      _regler(true, titre);

  /// À appeler dès que l'appel se termine, quelle qu'en soit la raison.
  /// Oublier cet appel laisse les verrous pris et la notification affichée.
  static Future<void> arreter() => _regler(false, null);

  static Future<void> _regler(bool actif, String? titre) async {
    if (!Platform.isAndroid) return;
    // L'état est suivi ici pour ne pas traverser le pont natif inutilement :
    // `demarrer` peut être appelé plusieurs fois pour un même appel, au fil des
    // participants qui rejoignent.
    if (_actif == actif) return;
    _actif = actif;
    try {
      if (actif) {
        await _canal.invokeMethod('demarrerServiceAppel', {'titre': titre});
      } else {
        await _canal.invokeMethod('arreterServiceAppel');
      }
    } catch (_) {
      // Canal absent (ancienne version installée par-dessus) ou service refusé
      // par le système : l'appel fonctionne quand même tant que l'application
      // reste à l'écran. Mieux vaut ça qu'un appel qui échoue à démarrer.
      _actif = !actif;
    }
  }
}
