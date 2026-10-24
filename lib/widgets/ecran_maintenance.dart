import 'package:flutter/material.dart';

import '../core/maintenance.dart';
import '../l10n/app_localizations.dart';
import '../theme/alanya_theme.dart';

/// L'ÉCRAN « EN MAINTENANCE » (24/10/2026), superposé à toute l'application
/// tant que le serveur est en maintenance (voir `core/maintenance.dart`).
///
/// Il disparaît seul quand la maintenance est levée — l'application vérifie
/// toutes les 20 s — ou au bouton « Réessayer ».
class EcranMaintenance extends StatelessWidget {
  const EcranMaintenance({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Maintenance.active,
      builder: (context, active, _) {
        if (!active) return const SizedBox.shrink();
        return Positioned.fill(
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.construction_rounded,
                      size: 72,
                      color: AlanyaColors.terracotta,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tr(context, 'maintenance_titre'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'maintenance_texte'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: Maintenance.verifier,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, 'maintenance_reessayer')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AlanyaColors.terracotta,
                        side: const BorderSide(color: AlanyaColors.terracotta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
