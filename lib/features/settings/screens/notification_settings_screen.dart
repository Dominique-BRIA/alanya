import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Notifications"),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline,
                color: AlanyaColors.forest),
            title: const Text("Notifications de messages"),
            subtitle: const Text("Bandeau et notification à chaque message reçu"),
            value: _s.messagesOn,
            onChanged: (v) {
              _s.setMessages(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.remove_red_eye_outlined,
                color: AlanyaColors.forest),
            title: const Text("Aperçu du message"),
            subtitle: const Text(
                "Afficher le contenu dans la notification (sinon « Nouveau message »)"),
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
            title: const Text("Notifications d'appels"),
            subtitle: const Text("Écran d'appel entrant quand l'app est fermée"),
            value: _s.callsOn,
            onChanged: (v) {
              _s.setCalls(v);
              setState(() {});
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Le son et la vibration se règlent dans les paramètres de notification Android d'Alanya.",
              style: TextStyle(fontSize: 12, color: AlanyaColors.grey500),
            ),
          ),
        ],
      ),
    );
  }
}
