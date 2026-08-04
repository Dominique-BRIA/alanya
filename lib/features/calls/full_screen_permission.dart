import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/call_ui_native.dart';

/// Demande, au premier lancement, l'autorisation d'ouvrir l'écran d'appel
/// par-dessus le verrouillage.
///
/// POURQUOI CE DÉTOUR. `POST_NOTIFICATIONS` se demande par une boîte de
/// dialogue système, en une ligne. `USE_FULL_SCREEN_INTENT` n'en a pas :
/// depuis Android 14 elle est refusée d'office aux applications qui ne sont pas
/// le téléphone du système, et la SEULE voie est d'ouvrir une page de réglages.
///
/// D'où l'explication maison affichée avant : envoyer quelqu'un sur une page
/// système sans lui dire pourquoi, c'est le meilleur moyen qu'il en sorte sans
/// rien activer.
class FullScreenPermission {
  FullScreenPermission._();

  static const _cle = 'plein_ecran_demande';

  /// À appeler une fois l'utilisateur arrivé sur l'accueil.
  ///
  /// Ne fait rien si l'autorisation est déjà acquise — le cas de tous les
  /// téléphones sous Android 14 — ni si la question a déjà été posée : on
  /// n'insiste pas à chaque ouverture. Le réglage reste accessible dans
  /// Réglages → Notifications pour qui a refusé puis changé d'avis.
  static Future<void> demanderSiNecessaire(BuildContext context) async {
    try {
      if (await CallUiNative.peutAfficherPleinEcran()) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_cle) ?? false) return;
      await prefs.setBool(_cle, true);

      if (!context.mounted) return;
      final accepte = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.phone_in_talk_outlined, size: 32),
          title: const Text("Afficher les appels en plein écran"),
          content: const Text(
            "Pour qu'un appel entrant s'affiche par-dessus l'écran verrouillé, "
            "comme sur un téléphone, Android demande une autorisation "
            "supplémentaire.\n\n"
            "Sans elle, l'appel n'apparaîtra qu'en notification et tu risques "
            "de le manquer.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Plus tard"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Autoriser"),
            ),
          ],
        ),
      );

      if (accepte == true) await CallUiNative.demanderPleinEcran();
    } catch (_) {
      // Une autorisation manquante ne doit jamais empêcher d'utiliser
      // l'application : au pire, les appels restent en notification.
    }
  }
}
