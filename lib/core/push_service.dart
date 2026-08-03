import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/src/platform_specifics/android/notification_sound.dart';

import '../core/api_client.dart';
// Préfixe : firebase_messaging exporte aussi un type `NotificationSettings`.
import '../core/notification_settings.dart' as notif;
import '../core/server_config.dart';
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

  /// Branché par la couche appel (CallListener) : reçoit l'action tapée sur la
  /// notification d'appel — 'call_accept' | 'call_reject' — avec le callId.
  /// Passe par un hook pour éviter un import core → features.
  ///
  /// L'affectation REJOUE une action restée en attente. C'est indispensable au
  /// démarrage à froid : l'action qui a lancé l'application est lue avant que
  /// `CallListener` n'existe, donc avant qu'il n'ait pu se brancher ici.
  static void Function(String actionId, String? callId)? get onCallAction =>
      _onCallAction;
  static set onCallAction(void Function(String, String?)? cb) {
    _onCallAction = cb;
    final enAttente = _actionEnAttente;
    if (cb != null && enAttente != null) {
      _actionEnAttente = null;
      cb(enAttente.$1, enAttente.$2);
    }
  }

  static void Function(String actionId, String? callId)? _onCallAction;

  /// Action d'appel reçue alors que personne n'écoutait encore.
  static (String, String?)? _actionEnAttente;

  /// Route une action d'appel, ou la met de côté si le destinataire n'est pas
  /// encore là.
  static void _emetActionAppel(String actionId, String? callId) {
    final cb = _onCallAction;
    if (cb != null) {
      cb(actionId, callId);
    } else {
      _actionEnAttente = (actionId, callId);
    }
  }

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
      // Actions tapées alors que l'application est en arrière-plan ou TUÉE.
      // Le plugin les livre dans un isolate séparé — voir
      // `notificationBackgroundHandler` en bas de ce fichier.
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    // ⚠️ INDISPENSABLE AU DÉMARRAGE À FROID, et ce n'est pas redondant avec le
    // rappel ci-dessus.
    //
    // Quand l'application est TUÉE et que l'utilisateur appuie sur « Répondre »
    // dans la notification d'appel, Android relance le processus. Mais
    // `onDidReceiveNotificationResponse` ne se déclenche PAS pour l'action qui
    // a provoqué ce lancement : elle a eu lieu avant que le plugin n'existe.
    // Elle n'est récupérable que par cette interrogation explicite.
    //
    // Sans elle, tout le reste de la chaîne était pourtant en place mais restait
    // inerte : `CallListener._pendingAccept` n'était jamais armé, l'application
    // s'ouvrait sur l'accueil et l'appel continuait de sonner chez l'appelant
    // jusqu'à expiration. C'est exactement le cas « app fermée », le plus
    // fréquent pour un appel entrant.
    await _traiteLancementParNotification();

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
    if (!notif.NotificationSettings.instance.messagesOn) return;

    final notification = message.notification;
    if (notification == null) return;

    final body =
        notif.NotificationSettings.instance.previewOn ? (notification.body ?? '') : 'Nouveau message';

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
          color: Color(0xFFB85C38),
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
    final actionId = response.actionId;
    Map<String, dynamic>? data;
    if (response.payload != null) {
      try {
        data = jsonDecode(response.payload!) as Map<String, dynamic>;
      } catch (_) {}
    }
    // Boutons Répondre / Refuser d'une notification d'appel.
    if (actionId == 'call_accept' || actionId == 'call_reject') {
      // Passe par `_emetActionAppel` et non plus directement par le callback :
      // l'action peut arriver avant que `CallListener` ne soit monté, auquel
      // cas elle est gardée puis rejouée à son branchement.
      _emetActionAppel(actionId!, data?['callId']?.toString());
      return;
    }
    if (data != null) _navigateFromPayload(data);
  }

  /// Récupère l'action de notification qui a LANCÉ l'application, s'il y en a
  /// une. Voir l'explication détaillée à l'appel, dans `_initLocalNotifications`.
  Future<void> _traiteLancementParNotification() async {
    try {
      final details = await _localPlugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      final reponse = details.notificationResponse;
      final actionId = reponse?.actionId;
      if (actionId != 'call_accept' && actionId != 'call_reject') return;

      String? callId;
      final payload = reponse?.payload;
      if (payload != null) {
        try {
          callId = (jsonDecode(payload) as Map)['callId']?.toString();
        } catch (_) {}
      }
      debugPrint('[PushService] Lancé par la notification d\'appel: $actionId');
      _emetActionAppel(actionId!, callId);
    } catch (e) {
      // Ne doit jamais empêcher le démarrage : sans cette reprise, l'app
      // s'ouvre normalement, l'appel n'est simplement pas décroché tout seul.
      debugPrint('[PushService] Lancement par notification illisible: $e');
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
          color: Color(0xFFB85C38),
          sound: RawResourceAndroidNotificationSound("notification"),
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload?.toString(),
    );
  }

  /// Désenregistre le token FCM (à la déconnexion).
  /// Tente d'utiliser le refresh token si l'access token est expiré,
  /// pour que le backend supprime bien l'association du token FCM.
  Future<void> unregister() async {
    try {
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      if (_fcmToken != null && _api != null && _storage != null) {
        String? accessToken = await _storage!.accessToken;
        // Si le token d'accès est expiré, on tente un refresh avant le DELETE
        // pour que le backend puisse identifier le compte et supprimer
        // l'association du token FCM.
        if (accessToken == null) {
          final refresh = await _storage!.refreshToken;
          if (refresh != null) {
            try {
              final data = await _api!.post(
                "/api/auth/refresh",
                {"refreshToken": refresh},
              );
              accessToken = data["accessToken"] as String?;
              final newRefresh = data["refreshToken"] as String?;
              if (accessToken != null && newRefresh != null) {
                await _storage!.saveTokens(
                  access: accessToken!,
                  refresh: newRefresh,
                );
              }
            } catch (_) {
              // Si le refresh échoue, on continue sans token valide.
            }
          }
        }
        if (accessToken != null) {
          await _api!.delete(
            '/api/push/register?token=$_fcmToken',
            bearer: accessToken,
          );
        } else {
          // Même sans token valide, on tente le DELETE : le backend
          // peut supprimer l'association côté serveur s'il connaît le token.
          await _api!.delete(
            '/api/push/register?token=$_fcmToken',
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
    if (!await notif.NotificationSettings.callsEnabledFresh()) return;
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
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('call_reject', 'Refuser',
                titleColor: Color(0xFFC62828), cancelNotification: true),
            AndroidNotificationAction('call_accept', 'Répondre',
                titleColor: Color(0xFF2D6A4F),
                showsUserInterface: true,
                cancelNotification: true),
          ],
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }
}

/// Refus d'un appel depuis la notification, **application tuée**.
///
/// POURQUOI UN HANDLER SÉPARÉ. Le bouton « Refuser » ne porte pas
/// `showsUserInterface` : c'est voulu, refuser un appel ne doit pas ouvrir
/// l'application. Mais Android ne relance alors aucun processus Flutter, donc
/// `onDidReceiveNotificationResponse` — qui vit dans l'isolate principal — n'est
/// jamais invoqué et le rejet ne partait jamais au serveur. L'appelant
/// continuait de sonner jusqu'à l'expiration des 90 s, en croyant que personne
/// ne décrochait alors que son correspondant avait explicitement refusé.
///
/// Ce point d'entrée est appelé par le plugin dans un isolate SANS INTERFACE.
/// Rien de l'application n'y est disponible : ni Provider, ni navigateur, ni
/// état en mémoire. Tout ce dont il a besoin doit être relu depuis le stockage.
///
/// `@pragma('vm:entry-point')` est indispensable : sans elle, la compilation
/// AOT de la version release supprime cette fonction, que rien n'appelle depuis
/// le code Dart. Le bug ne se verrait qu'en release, jamais en debug.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != 'call_reject') return;

  // L'isolate démarre nu : les plugins natifs doivent être ré-enregistrés,
  // sinon le stockage sécurisé et le réseau lèvent « MissingPluginException ».
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  String? callId;
  final payload = response.payload;
  if (payload != null) {
    try {
      callId = (jsonDecode(payload) as Map)['callId']?.toString();
    } catch (_) {}
  }
  if (callId == null || callId.isEmpty) return;

  try {
    final storage = TokenStorage();
    var token = await storage.accessToken;

    // Le jeton d'accès est de courte durée et l'application peut être fermée
    // depuis longtemps : sans ce rafraîchissement, le refus échouerait
    // silencieusement dans le cas le plus courant.
    if (token == null) {
      final refresh = await storage.refreshToken;
      if (refresh == null) return;
      final r = await http.post(
        Uri.parse('${ServerConfig.apiBase}/api/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );
      if (r.statusCode != 200) return;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      token = data['accessToken'] as String?;
      final nouveauRefresh = data['refreshToken'] as String?;
      if (token == null || nouveauRefresh == null) return;
      await storage.saveTokens(access: token, refresh: nouveauRefresh);
    }

    // `http` directement et non ApiClient : celui-ci dépend de l'arborescence
    // de widgets et de Provider, absents de cet isolate.
    await http.post(
      Uri.parse('${ServerConfig.apiBase}/api/calls/$callId/reject'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    // Aucun traitement de la réponse : un 409 signifie que l'appel était déjà
    // clos — raccroché en face, ou refusé depuis un autre appareil. C'est un
    // résultat acceptable, l'objectif étant seulement que l'appelant cesse de
    // sonner.
  } catch (_) {
    // L'isolate peut être tué à tout moment par le système. Échouer en silence
    // est le seul comportement possible : il n'y a ni interface où signaler
    // l'erreur, ni contexte où réessayer.
  }
}
