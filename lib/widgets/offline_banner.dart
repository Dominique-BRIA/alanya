import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/connectivity_service.dart';
import '../theme/alanya_theme.dart';
import '../l10n/app_localizations.dart';

/// « En attente de connexion… », quand l'app est hors ligne. Disparaît dès que
/// la connexion revient (voir [ConnectivityService] pour ce qui compte comme
/// « hors ligne »).
///
/// 🔴 UNE PASTILLE ROUGE QUI FLOTTE, PLUS UN BANDEAU (user, 30/10/2026 : « son
/// format n'est pas joli, mais j'aime bien la couleur rouge qui révèle
/// l'alerte »). Le bandeau gris, posé au-dessus de toute l'application,
/// passait sous la barre d'état et repoussait tout l'écran vers le bas à
/// chaque apparition. La pastille se pose SOUS la barre d'état, par-dessus
/// l'écran, sans rien déplacer ; elle laisse passer les touchers.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final horsLigne = context.watch<ConnectivityService>().isOffline;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                offset: horsLigne ? Offset.zero : const Offset(0, -1.5),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: horsLigne ? 1 : 0,
                  // ⚠️ Material INDISPENSABLE : posée par AuthGate hors de tout
                  // Scaffold, sans lui le texte prend le style de secours de
                  // Flutter, souligné de deux traits jaunes.
                  child: Material(
                    color: dangerOf(context),
                    elevation: 4,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 15, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            tr(context, 'waiting_for_connection_dots'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
