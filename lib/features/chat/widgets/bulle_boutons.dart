import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/message.dart';
import '../../../theme/alanya_theme.dart';
import '../../account/screens/profile_screen.dart';
import '../../home/home_screen.dart';
import '../../settings/screens/settings_screen.dart';

/// LA BULLE À BOUTONS d'un message officiel (24/10/2026).
///
/// Le bloc « Boutons » de la bienvenue de la console : des boutons qui ouvrent
/// un lien ou un écran de l'application. Le texte du message (« Libellé :
/// lien ») n'est PAS affiché : il n'existe que pour les versions de
/// l'application qui ignorent les boutons.
class BulleBoutons extends StatelessWidget {
  const BulleBoutons({
    super.key,
    required this.boutons,
    required this.timestamp,
    this.onLongPress,
  });

  final List<BoutonMessage> boutons;
  final String timestamp;
  final VoidCallback? onLongPress;

  /// Ouvre la destination d'un bouton.
  ///
  /// Un lien ne s'ouvre qu'en `http(s)` : le serveur ne pose que ce que la
  /// console a saisi, mais une adresse d'un autre schéma n'a rien à faire ici.
  /// Les écrans sont ceux que propose la console d'Alanya2026 : `profile`,
  /// `statuses`, `help` — l'aide n'ayant pas d'écran chez nous, elle ouvre les
  /// Paramètres.
  static Future<void> ouvrir(BuildContext context, BoutonMessage b) async {
    if (b.estLien) {
      final uri = Uri.tryParse(b.target);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    switch (b.target) {
      case 'profile':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      case 'statuses':
        // Retour à l'accueil, onglet des statuts.
        Navigator.of(context).popUntil((r) => r.isFirst);
        HomeScreen.ongletDemande.value = HomeScreen.ongletStatuts;
      case 'help':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AlanyaColors.grey200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in boutons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton.icon(
                  onPressed: () => ouvrir(context, b),
                  icon: Icon(
                    b.estLien ? Icons.open_in_new : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(b.label, textAlign: TextAlign.center),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AlanyaColors.terracotta,
                    side: const BorderSide(color: AlanyaColors.terracotta),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                timestamp,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
