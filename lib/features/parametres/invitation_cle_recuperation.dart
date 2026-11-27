import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../auth/auth_controller.dart';
import 'screens/sauvegarde_chiffree_screen.dart';

/// INVITER À NOTER LA CLÉ DE RÉCUPÉRATION, UNE FOIS (27/11/2026).
///
/// La sauvegarde est activée en silence, sans clé de récupération : la plupart
/// des comptes n'ont que la serrure « mot de passe ». Un mot de passe oublié
/// leur faisait alors perdre tout l'historique sur un nouvel appareil — et il
/// est trop tard, à ce moment-là, pour créer la clé.
///
/// On le propose donc UNE fois par compte et par appareil, quand l'archive est
/// ouverte et n'a pas encore de clé. « Plus tard » ne revient pas : la clé
/// reste offerte dans Réglages › Sauvegarde.
class InvitationCleRecuperation {
  InvitationCleRecuperation._();

  static Future<void> peutEtreProposer(BuildContext context) async {
    final pile = context.e2ee;
    if (pile == null || !pile.sauvegarde.estOuverte) return;
    final moi = context.read<AuthController>().user?.id;
    if (moi == null) return;
    final cle = 'invitation_cle_recuperation_vue_$moi';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(cle) == true) return;
    if (await pile.sauvegarde.aUneCleDeRecuperation()) {
      await prefs.setBool(cle, true);
      return;
    }
    if (!context.mounted) return;
    // Marquée AVANT d'afficher : une seule fois, même si l'écran se ferme.
    await prefs.setBool(cle, true);
    if (!context.mounted) return;
    final creer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_outlined),
        title: Text(tr(ctx, 'arch_invitation_titre')),
        content: Text(tr(ctx, 'arch_invitation_texte')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'arch_plus_tard')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'arch_invitation_creer')),
          ),
        ],
      ),
    );
    if (creer == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SauvegardeChiffreeScreen()),
      );
    }
  }
}
