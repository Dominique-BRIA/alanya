import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/connectivity_service.dart';

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
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: conn.isOffline ? 28 : 0,
          width: double.infinity,
          color: const Color(0xFF424242),
          alignment: Alignment.center,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: conn.isOffline ? 1 : 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                SizedBox(width: 8),
                Text(
                  "En attente de connexion…",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
