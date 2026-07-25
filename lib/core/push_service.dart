import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/src/platform_specifics/android/notification_sound.dart';

import '../core/api_client.dart';
import '../core/notification_settings.dart';
import '../core/token_storage.dart';

/// Service de notifications push complet (FCM + notifications locales).
///
/// ⚠️ Bug de timing corrigé : l'initialisation de Firebase (obtention du token)
/// et l'enregistrement du token auprès du backend sont SÉPARÉS.
/// - tryInitialize() : configure Firebase, le canal, et écoute le token.
/// - registerTokenIfAuthenticated() : envoie le token au backend. À appeler
///   UNIQUEMENT après que l'utilisateur soit authentifié.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  final _localPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  ApiClient? _api;
  TokenStorage? _storage;
  String? _fcmToken; // Token FCM obtenu au démarrage

  /// Initialise Firebase, les canaux de notification, et écoute le token.
  /// ⚠️ N'enregistre PAS le token auprès du backend (l'utilisateur n'est pas
  /// encore authentifié à ce stade). Appeler registerTokenIfAuthenticated()
  /// après le login.
  Future<void> tryInitialize({ApiClient? api, TokenStorage? storage}) async {
    if (_initialized) return;

    if (api != null) _api = api;
    if (storage != null) _storage = storage;

    try {
      // 1) Initialise Firebase Core
      await Firebase.initializeApp();

      // 2) Configure les notifications locales (canal Android)
      await _initLocalNotifications();

      // 3) Configure le callback d'arrière-plan (top-level function)
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // 4) Demande la permission
      await _requestPermission();

      // 5) Écoute les messages en foreground (app ouverte)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6) Écoute le tap sur notification quand l'app était en arrière-plan
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 7) Récupère le token FCM (sans l'envoyer au backend tout de suite)
      _fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('[PushService] Token FCM obtenu: $_fcmToken');

      // 8) Écoute les changements de token (refresh) → ré-enregistre si auth
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        registerTokenIfAuthenticated(); // ré-enregistre si l'utilisateur est co
      });

      _initialized = true;
      debugPrint('[PushService] Firebase initialisé avec succès');
    } catch (e) {
      debugPrint('[PushService] Erreur initialisation: $e');
    }
  }

  /// Enregistre le token FCM auprès du backend.
  /// À appeler APRÈS l'authentification (login ou bootstrap réussi).
  /// Peut être appelé plusieurs fois sans risque (idempotent).
  Future<void> registerTokenIfAuthenticated() async {
    try {
      // S'assure que Firebase est initialisé
      if (!_initialized) {
        await tryInitialize();
      }

      // Récupère le token si pas déjà en cache
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      if (_fcmToken == null) {
        debugPrint('[PushService] Token FCM null, impossible d\'enregistrer');
        return;
      }

      // Vérifie qu'on est bien authentifié avant d'envoyer
      if (_api == null || _storage == null) {
        debugPrint('[PushService] API/Storage non configuré, enregistrement annulé');
        return;
      }
      final accessToken = await _storage!.accessToken;
      if (accessToken == null) {
        debugPrint('[PushService] Utilisateur non authentifié, enregistrement annulé');
        return;
      }

      // Envoie le token au backend via POST /api/push/register
      await _api!.post(
        '/api/push/register',
        {'token': _fcmToken, 'platform': 'android'},
        bearer: accessToken,
      );
      debugPrint('[PushService] ✅ Token enregistré auprès du backend');
    } catch (e) {
      debugPrint('[PushService] Erreur enregistrement token: $e');
    }
  }

  /// Initialise les notifications locales (crée le canal Android).
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Crée le canal Android obligatoire (Android 8+)
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Notifications des nouveaux messages et appels',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound("notification"),
      );
      await _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Canal dédié aux appels entrants (plein écran).
      await _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(callChannel);
    }
  }

  /// Canal Android des appels entrants (importance max + full-screen intent).
  static const callChannel = AndroidNotificationChannel(
    'calls',
    'Appels',
    description: 'Appels entrants',
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
    sound: RawResourceAndroidNotificationSound("notification"),
  );

  /// Affiche une notification d'appel entrant PLEIN ÉCRAN (full-screen intent),
  /// même écran verrouillé / app fermée. À déclencher depuis le handler FCM
  /// quand `data.type == "incoming_call"`.
  /// Id de notification dérivé du callId (0 = fallback si inconnu) → permet
  /// d'annuler précisément l'appel concerné, même si plusieurs se suivent.
  static int callNotifId(String? callId) =>
      callId == null || callId.isEmpty ? 9911 : (callId.hashCode & 0x7fffffff);

  Future<void> showIncomingCall({
    required String title,
    required String body,
    String? callId,
  }) async {
    await _localPlugin.show(
      callNotifId(callId),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'calls',
          'Appels',
          channelDescription: 'Appels entrants',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          // Filet de sécurité : Android retire la notif tout seul après ~60 s
          // (durée de sonnerie) — couvre le cas où le push d'annulation
          // n'arrive pas (app « force stop »).
          timeoutAfter: 60000,
          icon: '@mipmap/ic_launcher',
          sound: RawResourceAndroidNotificationSound("notification"),
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: null,
    );
  }

  /// Retire la notification d'appel (quand répondu / annulé). Cible l'appel
  /// [callId] si fourni, sinon l'id de repli.
  Future<void> cancelIncomingCall([String? callId]) =>
      _localPlugin.cancel(callNotifId(callId));

  /// Demande la permission (Android 13+ POST_NOTIFICATIONS + iOS).
  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[PushService] Permission: ${settings.authorizationStatus}');
  }

  /// Gère les messages reçus quand l'app est en premier plan (foreground).
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[PushService] Message foreground: ${message.notification?.title}');

    // Appel entrant : géré en temps réel par le WebSocket (écran/bandeau
    // d'appel) → pas de notif FCM en double quand l'app est ouverte.
    if (message.data['type'] == 'incoming_call') return;

    // Réglage : notifications de messages désactivées → on n'affiche rien.
    if (!NotificationSettings.instance.messagesOn) return;

    final notification = message.notification;
    if (notification == null) return;

    final body =
        NotificationSettings.instance.previewOn ? (notification.body ?? '') : 'Nouveau message';

    _localPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      notification.title ?? 'Alanya',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          'Messages',
          channelDescription: 'Notifications des nouveaux messages et appels',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          sound: RawResourceAndroidNotificationSound("notification"),
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _navigateFromPayload(message.data);
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _navigateFromPayload(data);
      } catch (_) {}
    }
  }

  void _navigateFromPayload(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final convId = data['convId'] as String?;
    debugPrint('[PushService] Navigation vers conv: $convId (type: $type)');
  }

  /// Affiche une notification locale.
  Future<void> show({
    required String title,
    required String body,
    int id = 0,
    Map<String, dynamic>? payload,
  }) async {
    await _localPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          'Messages',
          channelDescription: 'Notifications des nouveaux messages et appels',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          sound: RawResourceAndroidNotificationSound("notification"),
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload?.toString(),
    );
  }

  /// Désenregistre le token FCM (à la déconnexion).
  Future<void> unregister() async {
    try {
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      if (_fcmToken != null && _api != null && _storage != null) {
        final accessToken = await _storage!.accessToken;
        if (accessToken != null) {
          await _api!.delete(
            '/api/push/register?token=$_fcmToken',
            bearer: accessToken,
          );
        }
      }
      await FirebaseMessaging.instance.deleteToken();
      _fcmToken = null;
    } catch (e) {
      debugPrint('[PushService] Erreur unregister: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[PushService] Message background: ${message.data['type']}');

  // Appel annulé/terminé par l'appelant → retire la notif d'appel plein écran
  // (ciblée par le callId partagé WS/FCM).
  if (message.data['type'] == 'call_cancelled') {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(PushService.callNotifId(message.data['callId']?.toString()));
    return;
  }

  // Appel entrant (app fermée/arrière-plan) → notification PLEIN ÉCRAN.
  // Ne se déclenche que si le push est data-only (pas de bloc notification).
  if (message.data['type'] == 'incoming_call') {
    // Réglage : notifications d'appels désactivées → on n'affiche rien.
    if (!await NotificationSettings.callsEnabledFresh()) return;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    if (Platform.isAndroid) {
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(PushService.callChannel);
    }
    final data = message.data;
    final title = data['callerName']?.toString() ?? 'Appel entrant';
    final body = (data['callType'] == 'VIDEO')
        ? 'Appel vidéo entrant'
        : 'Appel audio entrant';
    await plugin.show(
      PushService.callNotifId(data['callId']?.toString()),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'calls',
          'Appels',
          channelDescription: 'Appels entrants',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          // Filet de sécurité : Android retire la notif tout seul après ~60 s
          // (durée de sonnerie) — couvre le cas où le push d'annulation
          // n'arrive pas (app « force stop »).
          timeoutAfter: 60000,
          icon: '@mipmap/ic_launcher',
          sound: RawResourceAndroidNotificationSound("notification"),
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
