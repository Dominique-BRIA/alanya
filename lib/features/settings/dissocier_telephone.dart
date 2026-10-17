import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/device_registry.dart';
import '../../core/realtime_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../theme/alanya_theme.dart';
import '../auth/auth_controller.dart';
import 'deconnexion.dart';

/// Un compte, un téléphone (28/09/2026).
///
/// Le compte est LIÉ au téléphone sur lequel il s'est connecté : un autre
/// téléphone est refusé tant que celui-ci n'a pas été dissocié. Une
/// déconnexion ordinaire ne dissocie rien. Ce fichier porte le geste qui
/// libère le compte, appelé depuis les Paramètres et depuis la ligne de ce
/// téléphone dans « Appareils connectés » — un seul chemin pour les deux.

/// « Dissocier ce téléphone » : confirmation, puis le compte est libéré et
/// l'utilisateur déconnecté.
///
/// Ordre des étapes, et chacune a sa raison :
///
///  1. le serveur libère le compte et coupe les sessions des téléphones ;
///  2. l'identité de chiffrement est retirée du serveur. Il ne sait pas la
///     retirer seul (il ne relie pas le numéro d'appareil Signal au
///     téléphone), et la déconnexion ordinaire ne la retire pas : sans ce
///     retrait, les correspondants continueraient de chiffrer pour un téléphone
///     qui ne lira plus jamais rien, jusqu'au balayage des 30 jours.
///     ⚠️ APRÈS la dissociation, jamais avant : si celle-ci échouait, le
///     téléphone resterait connecté SANS identité publiée — personne ne
///     pourrait plus lui écrire, et rien ne la republie. Le jeton d'accès
///     reste valable quelques minutes après la révocation, ce qui suffit. Un
///     échec n'empêche pas la suite ;
///  3. les AUTRES téléphones coupés sont annoncés au temps réel, pour qu'ils
///     n'attendent pas l'expiration de leur jeton (restes d'avant la règle) ;
///  4. la déconnexion locale, avec un message qui dit ce qui s'est passé.
///
/// ⚠️ SI LE SERVEUR REFUSE, ON NE DÉCONNECTE PAS. Se déconnecter sans avoir
/// dissocié laisserait l'utilisateur croire son compte libre : il irait sur
/// son nouveau téléphone et y serait refusé.
Future<void> dissocierCeTelephone(BuildContext context) async {
  final continuer = await confirmerPerteChiffree(
    context,
    action: tr(context, 'dissoc_action'),
  );
  if (!continuer || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr(context, 'dissoc_q')),
      content: Text(tr(context, 'dissoc_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr(context, 'cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(
            tr(context, 'dissoc_action'),
            style: TextStyle(color: dangerOf(context)),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final auth = context.read<AuthController>();
  final realtime = context.read<RealtimeClient>();
  final pile = context.e2ee;
  final message = tr(context, 'dissoc_done');
  final echec = tr(context, 'dissoc_failed');

  final List<String> telephones;
  try {
    telephones = await DeviceRegistry.instance.dissocier();
  } catch (_) {
    showAppSnackBar(echec);
    return;
  }

  // Identité retirée du serveur ET coffre vidé — sans quoi un téléphone
  // reconnecté plus tard ne republiait jamais (voir `oublierCetAppareil`).
  await pile?.service.oublierCetAppareil();

  final moi = await DeviceRegistry.instance.deviceId();
  for (final id in telephones) {
    if (id != moi) {
      realtime.sendSessionRevoked(
        id,
        raison: AuthController.raisonDissociation,
      );
    }
  }

  auth.messageDeconnexion = message;
  await auth.logout();
}
