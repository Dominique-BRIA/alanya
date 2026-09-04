import 'dart:io';
import '../../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/notification_settings.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';

/// Réglages des notifications (device-level).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _s = NotificationSettings.instance;

  /// Ouvre le réglage Android de l'autorisation « plein écran ».
  ///
  /// Sur Android 14 et suivants, le plugin renvoie vers la page système
  /// correspondante : l'autorisation ne peut pas être accordée par le code, il
  /// faut que l'utilisateur bascule l'interrupteur lui-même. En dessous
  /// d'Android 14 elle est déjà acquise et l'appel n'a aucun effet visible,
  /// d'où le message qui l'explique plutôt que de laisser croire à une panne.
  Future<void> _demandeOuvertureAutomatique() async {
    final plugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;
    final accorde = await plugin.requestFullScreenIntentPermission();
    if (!mounted) return;
    showAppSnackBar(accorde == true
        ? tr(context, 'notif_perm_granted')
        : tr(context, 'notif_perm_hint'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'set_notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: Icon(Icons.chat_bubble_outline,
                color: themed(context,
                    light: AlanyaColors.forest,
                    dark: AlanyaColors.indigoLight)),
            title: Text(tr(context, 'notif_messages')),
            subtitle: Text(tr(context, 'notif_messages_sub')),
            value: _s.messagesOn,
            onChanged: (v) {
              _s.setMessages(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.remove_red_eye_outlined,
                color: themed(context,
                    light: AlanyaColors.forest,
                    dark: AlanyaColors.indigoLight)),
            title: Text(tr(context, 'notif_preview')),
            subtitle: Text(
                tr(context, 'notif_preview_sub')),
            value: _s.previewOn,
            onChanged: _s.messagesOn
                ? (v) {
                    _s.setPreview(v);
                    setState(() {});
                  }
                : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary:
                const Icon(Icons.call_outlined, color: AlanyaColors.terracotta),
            title: Text(tr(context, 'notif_calls')),
            subtitle: Text(tr(context, 'notif_calls_sub')),
            value: _s.callsOn,
            onChanged: (v) {
              _s.setCalls(v);
              setState(() {});
            },
          ),
          // Écran d'appel qui s'ouvre TOUT SEUL, sans toucher la notification.
          //
          // Ce comportement dépend d'une autorisation Android à part, et c'est
          // ce qui explique qu'il fonctionne sur un téléphone et pas sur un
          // autre : jusqu'à Android 13 elle était accordée d'office, depuis
          // Android 14 elle est REFUSÉE par défaut à toute application qui
          // n'est pas le téléphone du système. La déclarer dans le manifeste ne
          // suffit donc plus, il faut que l'utilisateur l'accorde lui-même.
          if (Platform.isAndroid)
            ListTile(
              leading:
                  const Icon(Icons.fullscreen, color: AlanyaColors.terracotta),
              title: Text(tr(context, 'notif_auto_open')),
              subtitle: Text(
                  tr(context, 'notif_auto_open_sub')),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: _demandeOuvertureAutomatique,
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(context, 'notif_android_hint'),
              style: TextStyle(
                  fontSize: 12,
                  color: themed(context,
                      light: AlanyaColors.grey500, dark: AlanyaColors.craie2)),
            ),
          ),
        ],
      ),
    );
  }
}
