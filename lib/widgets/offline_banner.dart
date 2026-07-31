import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/connectivity_service.dart';
import '../theme/alanya_theme.dart';

/// Bannière grise "Sans connexion" affichée en haut de l'écran quand l'app
/// est offline. Disparaît automatiquement dès que la connexion revient.
/// Style inspiré de WhatsApp.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityService>();
    return Column(
      children: [
        // ⚠️ Material INDISPENSABLE, et ce n'est pas de la décoration.
        //
        // Ce bandeau est posé par AuthGate au-dessus de tout, donc en dehors de
        // tout Scaffold : son Text n'avait AUCUN Material au-dessus de lui.
        // Dans ce cas Flutter n'applique pas le style du thème mais son style
        // de secours de débogage — celui qui souligne le texte de DEUX TRAITS
        // JAUNES. C'était l'origine du « trait jaune » sous « En attente de
        // connexion… », un artefact de rendu et non un choix graphique.
        //
        // Le Material fournit le DefaultTextStyle manquant ; le soulignement
        // est en outre coupé explicitement, pour que la correction ne dépende
        // pas d'un détail d'implémentation de Flutter.
        Material(
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            height: conn.isOffline ? 28 : 0,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF424242),
              // Le trait sous le bandeau, demandé en rouge : un vrai liseré
              // dessiné, à la place du soulignement parasite.
              border: Border(
                bottom: BorderSide(color: dangerOf(context), width: 2),
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: conn.isOffline ? 1 : 0,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    "En attente de connexion…",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
