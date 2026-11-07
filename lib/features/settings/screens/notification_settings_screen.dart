import 'dart:io';
import '../../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../../core/notification_settings.dart';
import '../../calls/fiabilite_appels.dart';
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
          // Il dépend de plusieurs réglages du téléphone (plein écran,
          // superposition, canal d'appels, batterie), chacun capable de
          // l'empêcher en silence : l'écran « Fiabilité des appels » fait le
          // point et mène à chacun (07/11/2026).
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.phone_in_talk_outlined,
                  color: AlanyaColors.terracotta),
              title: Text(tr(context, 'callrel_screen_title')),
              subtitle: Text(tr(context, 'callrel_settings_sub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const EcranFiabiliteAppels(),
              )),
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
