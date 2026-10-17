/// SE DÉCONNECTER, avec les mêmes gardes depuis les réglages et depuis le profil.
///
/// ⚠️ UNE SEULE DÉFINITION. L'écran Profil avait son propre bouton, qui
/// déconnectait sans rien demander — ni confirmation, ni l'avertissement sur
/// les messages chiffrés sans sauvegarde que les réglages, eux, affichaient.
/// Deux chemins vers le même geste doivent avoir les mêmes gardes.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../theme/alanya_theme.dart';
import '../auth/auth_controller.dart';

/// Se déconnecter en quittant CET appareil : identité de chiffrement retirée
/// du serveur, coffre vidé, puis session fermée.
///
/// 🔴 LE SEUL CHEMIN DE DÉCONNEXION. Quatre écrans appelaient
/// `AuthController.logout()` directement, et aucun ne vidait le coffre :
/// l'identité privée, les sessions et la clé de l'archive restaient sur le
/// téléphone. Voir `E2eeService.oublierCetAppareil`.
///
/// ⚠️ LA PILE ET LE CONTRÔLEUR SONT LUS AVANT TOUT `await` : l'écran qui
/// appelle peut disparaître pendant le retrait.
Future<void> seDeconnecter(BuildContext context) async {
  final pile = context.e2ee;
  final auth = context.read<AuthController>();
  await pile?.service.oublierCetAppareil();
  await auth.logout();
}

/// Avertit si des messages chiffrés vont être perdus ; `true` = continuer.
///
/// 🔴 ON AVERTIT SI LA SAUVEGARDE MANQUE, et c'est le seul moment où cela sert
/// encore. Quitter l'appareil efface le coffre et purge le cache — deux
/// décisions justes — et les enveloppes sont acquittées : l'historique chiffré
/// disparaît, sans que rien ne le dise.
///
/// ⚠️ ON AVERTIT, ON N'EMPÊCHE PAS. Se déconnecter est un geste de sécurité :
/// quelqu'un qui quitte un poste partagé doit pouvoir le faire tout de suite.
///
/// ⚠️ ET SEULEMENT S'IL Y A QUELQUE CHOSE À PERDRE. Un avertissement qui
/// s'affiche à tout le monde à chaque fois cesse d'être lu.
///
/// Partagé avec « Dissocier ce téléphone » (`dissocier_telephone.dart`), qui
/// quitte l'appareil de la même façon et perd la même chose.
Future<bool> confirmerPerteChiffree(
  BuildContext context, {
  required String action,
}) async {
  final pile = context.e2ee;
  if (pile == null || pile.fil.conversationsChiffrees() == 0) return true;
  final coffre = await pile.sauvegarde.lireCoffre();
  if (coffre.serrures.isNotEmpty || !context.mounted) return true;
  final quandMeme = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Vos messages chiffrés seront perdus'),
      content: const Text(
        'Vous avez des conversations chiffrées et aucune '
        'sauvegarde. En quittant cet appareil, ces messages '
        'seront définitivement perdus : ils ne vivent que sur '
        'cet appareil, et personne — nous compris — ne peut '
        'les retrouver.',
        style: TextStyle(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return quandMeme == true;
}

Future<void> confirmerDeconnexion(BuildContext context) async {
  final continuer = await confirmerPerteChiffree(
    context,
    action: 'Se déconnecter quand même',
  );
  if (!continuer || !context.mounted) return;
  final danger = themed(
    context,
    light: Colors.red,
    dark: AlanyaColors.erreurNuit,
  );
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(tr(context, 'set_logout_q')),
      content: Text(tr(context, 'set_logout_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, 'cancel')),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            seDeconnecter(context);
          },
          child: Text(
            tr(context, 'set_logout_action'),
            style: TextStyle(color: danger),
          ),
        ),
      ],
    ),
  );
}
