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

Future<void> confirmerDeconnexion(BuildContext context) async {
  /*
   * 🔴 ON AVERTIT SI LA SAUVEGARDE MANQUE, et c'est le seul moment où cela sert
   * encore. Se déconnecter efface le coffre et purge le cache — deux décisions
   * justes — et les enveloppes sont acquittées : l'historique chiffré
   * disparaît, sans que rien ne le dise.
   *
   * ⚠️ ON AVERTIT, ON N'EMPÊCHE PAS. Se déconnecter est un geste de sécurité :
   * quelqu'un qui quitte un poste partagé doit pouvoir le faire tout de suite.
   *
   * ⚠️ ET SEULEMENT S'IL Y A QUELQUE CHOSE À PERDRE. Un avertissement qui
   * s'affiche à tout le monde à chaque fois cesse d'être lu.
   */
  final pile = context.e2ee;
  if (pile != null && pile.fil.conversationsChiffrees() > 0) {
    final coffre = await pile.sauvegarde.lireCoffre();
    if (coffre.serrures.isEmpty && context.mounted) {
      final quandMeme = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Vos messages chiffrés seront perdus'),
          content: const Text(
            'Vous avez des conversations chiffrées et aucune '
            'sauvegarde. En vous déconnectant, ces messages '
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
              child: const Text('Se déconnecter quand même'),
            ),
          ],
        ),
      );
      if (quandMeme != true) return;
    }
  }
  if (!context.mounted) return;
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
            context.read<AuthController>().logout();
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
