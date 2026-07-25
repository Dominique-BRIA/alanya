import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences de notifications (device-level, comme WhatsApp).
///
/// - [messages] : notifications de nouveaux messages (bandeau in-app + notif).
/// - [calls]    : notification plein écran d'appel entrant (app fermée).
/// - [preview]  : afficher le contenu du message dans la notif (sinon générique).
///
/// Singleton synchrone (lu par les déclencheurs sans provider) + persistance.
/// Réglages de son/vibration : gérés par le canal système Android (hors app).
class NotificationSettings {
  NotificationSettings._();
  static final NotificationSettings instance = NotificationSettings._();

  static const _kMessages = 'notif_messages';
  static const _kCalls = 'notif_calls';
  static const _kPreview = 'notif_preview';

  final ValueNotifier<bool> messages = ValueNotifier<bool>(true);
  final ValueNotifier<bool> calls = ValueNotifier<bool>(true);
  final ValueNotifier<bool> preview = ValueNotifier<bool>(true);

  bool get messagesOn => messages.value;
  bool get callsOn => calls.value;
  bool get previewOn => preview.value;

  /// À appeler au démarrage (main), avant les premiers déclencheurs de notif.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      messages.value = p.getBool(_kMessages) ?? true;
      calls.value = p.getBool(_kCalls) ?? true;
      preview.value = p.getBool(_kPreview) ?? true;
    } catch (_) {}
  }

  Future<void> setMessages(bool v) => _set(_kMessages, messages, v);
  Future<void> setCalls(bool v) => _set(_kCalls, calls, v);
  Future<void> setPreview(bool v) => _set(_kPreview, preview, v);

  Future<void> _set(String key, ValueNotifier<bool> n, bool v) async {
    n.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  /// Lecture fraîche (isolate d'arrière-plan FCM, où le singleton n'est pas
  /// chargé) : les notifications d'appels sont-elles activées ?
  static Future<bool> callsEnabledFresh() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_kCalls) ?? true;
    } catch (_) {
      return true;
    }
  }
}
