import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';

/// LE JOURNAL DES CRASHS, côté Flutter (21/11/2026).
///
/// Le code natif (`JournalCrash.kt`) écrit le dernier crash avant que le
/// système ne ferme l'application. Au lancement suivant, on le montre une
/// seule fois, avec de quoi le partager ; le fichier est ensuite effacé, qu'il
/// ait été partagé ou non.
class CrashJournal {
  static const _canal = MethodChannel('com.alanya/call_native');

  static Future<void> verifierAuDemarrage(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    String? texte;
    try {
      texte = await _canal.invokeMethod<String>('lireDernierCrash');
    } catch (_) {
      return;
    }
    if (texte == null || texte.trim().isEmpty || !context.mounted) return;
    // Effacé AVANT d'afficher : si l'écran se ferme sans réponse, le même
    // crash ne revient pas à chaque lancement.
    try {
      await _canal.invokeMethod('effacerDernierCrash');
    } catch (_) {}
    if (!context.mounted) return;
    final rapport = texte;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx);
        return AlertDialog(
          icon: const Icon(Icons.bug_report_outlined),
          title: Text(t.get('crash_titre')),
          content: Text(t.get('crash_texte')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.get('crash_fermer')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: Text(t.get('crash_partager')),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await SharePlus.instance.share(ShareParams(text: rapport));
                } catch (_) {}
              },
            ),
          ],
        );
      },
    );
  }
}
