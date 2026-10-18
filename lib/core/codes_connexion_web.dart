import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';
import 'authed_api.dart';
import 'push_service.dart';
import 'realtime_client.dart';

/// LE CODE D'UNE CONNEXION WEB, affiché dans l'application (18/10/2026).
///
/// 🔴 DEMANDE DU PATRON : pour se connecter sur le web, « on l'envoie OTP dans
/// l'application Android, qu'on saisit pour entrer ». Le serveur
/// (`deux-etapes.ts`) envoie le code par la trame `connexion_web_code`, et par
/// une notification : application en veille, c'est elle qu'on voit ;
/// application ouverte, c'est cette fenêtre.
///
/// « Ce n'est pas moi » rend le code inutilisable tout de suite — quelqu'un a
/// le mot de passe : la fenêtre conseille de le changer.
///
/// ⚠️ UNE FENÊTRE PAR DÉFI : la trame et la notification arrivent souvent
/// toutes les deux ; la seconde ne rouvre rien.
class CodesConnexionWeb {
  CodesConnexionWeb._();
  static final instance = CodesConnexionWeb._();

  final Set<String> _vus = {};
  StreamSubscription<Map<String, dynamic>>? _abonnement;
  AuthedApi? _api;

  /// À l'ouverture de la session.
  void demarrer(RealtimeClient rt, AuthedApi api) {
    _api = api;
    _abonnement?.cancel();
    _abonnement = rt.events.listen((e) {
      if (e['type'] == 'connexion_web_code') afficher(e);
    });
  }

  void arreter() {
    _abonnement?.cancel();
    _abonnement = null;
  }

  /// Affiche le code de [donnees] (`defiId`, `code`, `navigateur`).
  void afficher(Map<String, dynamic> donnees) {
    final defiId = donnees['defiId']?.toString() ?? '';
    final code = donnees['code']?.toString() ?? '';
    if (defiId.isEmpty || code.length != 6 || !_vus.add(defiId)) return;
    final ctx = PushService.navigatorKey.currentContext;
    if (ctx == null) return;
    final navigateur = donnees['navigateur']?.toString() ?? '';
    final lisible = '${code.substring(0, 3)} ${code.substring(3)}';

    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.lock_person_outlined, size: 32),
        title: Text(tr(d, 'cw_titre')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(d, 'cw_corps'), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          // Un appui le copie : on le recopie souvent sur un autre écran.
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Clipboard.setData(ClipboardData(text: code)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SelectableText(
                lisible,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          if (navigateur.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tr(d, 'cw_navigateur', {'nav': navigateur}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Text(tr(d, 'cw_validite'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              unawaited(_refuser(defiId));
              showAppSnackBar(tr(ctx, 'cw_refuse_toast'));
            },
            child: Text(tr(d, 'cw_pas_moi'),
                style: const TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: Text(tr(d, 'ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _refuser(String defiId) async {
    try {
      await _api?.post('/api/auth/login/refuser', {'defiId': defiId});
    } catch (_) {
      // Hors ligne : le code expirera seul dans cinq minutes.
    }
  }
}
