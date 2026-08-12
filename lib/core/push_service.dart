import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/src/platform_specifics/android/notification_sound.dart';

import '../core/api_client.dart';
import 'device_registry.dart';
import 'geo_service.dart';
// Préfixe : firebase_messaging exporte aussi un type `NotificationSettings`.
import '../core/call_ui_native.dart';
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

      // 3 bis) Même chose pour l'ÉCRAN D'APPEL NATIF. Sans cet enregistrement,
      // refuser un appel application tuée n'atteignait jamais le serveur :
      // l'écouteur du premier plan vit dans un widget qui n'existe pas alors,
      // et refuser n'ouvre pas l'application. L'appelant sonnait dans le vide
      // jusqu'à l'expiration du minuteur.
      try {
        await FlutterCallkitIncoming.onBackgroundMessage(
          callkitBackgroundHandler,
        );
      } catch (e) {
        // Enregistrement refusé (plateforme sans support) : le premier plan
        // continue de fonctionner, seul le cas « application tuée » est perdu.
        debugPrint('[PushService] handler d\'appel en arrière-plan absent: $e');
      }

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
        debugPrint(
            '[PushService] API/Storage non configuré, enregistrement annulé');
        return;
      }
      final accessToken = await _storage!.accessToken;
      if (accessToken == null) {
        debugPrint(
            '[PushService] Utilisateur non authentifié, enregistrement annulé');
        return;
      }

      // Envoie le token au backend via POST /api/push/register
      await _api!.post(
        '/api/push/register',
        {
          'token': _fcmToken,
          'platform': 'android',
          // ⚠️ Rattache le jeton à CET appareil. Sans lui, l'envoi ne cible
          // qu'un compte : un téléphone déconnecté ou évincé continuait de
          // recevoir messages et appels, faute de savoir en base quel jeton lui
          // appartenait. C'est ce qui permet au serveur de couper à la
          // déconnexion, sans dépendre d'un `DELETE` que l'application n'a pas
          // toujours le temps — ni le jeton valide — d'envoyer.
          'deviceId': await DeviceRegistry.instance.deviceId(),
        },
        bearer: accessToken,
      );
      debugPrint('[PushService] ✅ Token enregistré auprès du backend');
    } catch (e) {
      debugPrint('[PushService] Erreur enregistrement token: $e');
    }
  }

  /// Initialise les notifications locales (crée le canal Android).
  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

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

  /// Identifiant fixe : un seul rappel de localisation à la fois. Le rejouer
  /// remplace le précédent au lieu d'en empiler un à chaque connexion.
  ///
  /// ⚠️ PUBLIC parce que l'ISOLAT du service de premier plan repose et retire la
  /// MÊME notification quand l'application est fermée. Deux identifiants
  /// différents laisseraient deux rappels côte à côte.
  static const idRappelLocalisation = 9921;

  static const titreRappelLocalisation = "Localisation désactivée";
  static const texteRappelLocalisation =
      "Votre position n'est plus transmise à votre entreprise. "
      "Appuyez pour réactiver la localisation.";

  /// Habillage du rappel, extrait pour que l'application et l'isolat posent
  /// EXACTEMENT la même notification — deux définitions finiraient par diverger,
  /// et l'utilisateur verrait un rappel différent selon que l'application est
  /// ouverte ou fermée.
  ///
  /// `permanent` rend la notification **non balayable** (`ongoing`) : le doigt
  /// ne la fait plus disparaître, et « Tout effacer » ne l'emporte pas.
  ///
  /// 🔴 CE N'EST PAS SUFFISANT SEUL, ET C'EST UNE LIMITE D'ANDROID, PAS DU CODE :
  /// **depuis Android 14, une notification `ongoing` redevient balayable**
  /// lorsque le téléphone est déverrouillé (seuls les appels, les sessions média
  /// et les applications de gestion d'entreprise en sont exemptés). La promesse
  /// « elle reste tant que la localisation est coupée » est donc tenue par la
  /// VEILLE qui la repose (`GeoService._signaleLocalisationCoupee` quand
  /// l'application vit, `geo_background` quand elle est fermée), pas par ce
  /// drapeau. Le drapeau couvre Android 13 et antérieurs, la veille couvre le
  /// reste.
  ///
  /// `onlyAlertOnce` est ce qui rend la veille invisible : reposer la
  /// notification ne fait ni vibrer ni sonner, elle réapparaît simplement.
  static NotificationDetails detailsRappelLocalisation({
    required bool permanent,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'localisation',
        'Localisation',
        channelDescription: "Rappels lorsque la localisation est désactivée",
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: permanent,
        autoCancel: !permanent,
        onlyAlertOnce: true,
      ),
    );
  }

  /// Charge utile du rappel, commune aux deux isolats.
  static String get payloadRappelLocalisation =>
      jsonEncode({'type': 'geo_rappel'});

  /// Rappelle à un agent que sa localisation est coupée.
  ///
  /// ⚠️ N'EST ENVOYÉ QU'À QUELQU'UN QUI A ACCEPTÉ LE SUIVI puis désactivé sa
  /// localisation — la garde est dans `GeoService.demarrer`. Celui qui a refusé
  /// n'est jamais relancé : la règle du Play Store l'interdit, et insister ne
  /// fait pas changer d'avis.
  ///
  /// Un appui ouvre directement les réglages de localisation du système : c'est
  /// le seul endroit où le GPS se rallume, et y envoyer quelqu'un sans le dire
  /// serait le meilleur moyen qu'il en ressorte sans rien faire.
  ///
  /// ⚠️ `permanent: false` n'est PAS un réglage de confort : voir la garde de
  /// `GeoService.demarrer`. Une notification non balayable ne se retire que par
  /// du code ; si personne ne peut plus l'exécuter — permission refusée, donc
  /// pas de service de premier plan pour faire la veille — elle resterait
  /// affichée à vie, y compris une fois le problème résolu.
  Future<void> showRappelLocalisation({bool permanent = true}) async {
    try {
      await _localPlugin.show(
        idRappelLocalisation,
        titreRappelLocalisation,
        texteRappelLocalisation,
        detailsRappelLocalisation(permanent: permanent),
        payload: payloadRappelLocalisation,
      );
    } catch (e) {
      debugPrint('[PushService] rappel de localisation impossible : $e');
    }
  }

  /// Retire le rappel dès que la localisation est rallumée : le laisser
  /// afficher un problème résolu ferait douter de tous les autres.
  Future<void> retireRappelLocalisation() async {
    try {
      await _localPlugin.cancel(idRappelLocalisation);
    } catch (_) {}
  }

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
    debugPrint(
        '[PushService] Message foreground: ${message.notification?.title}');

    // Appel entrant, application ouverte : c'est le WebSocket qui l'annonce,
    // avec le bandeau interne et la sonnerie de l'application. Déclarer ici
    // l'écran natif ferait doublon avec ce bandeau.
    if (message.data['type'] == 'incoming_call') return;

    // Réunions (invitation, rappel avant le début) — traitées AVANT le réglage
    // ci-dessous, qui ne gouverne que les messages. Une invitation n'en est pas
    // un : la faire taire parce que l'utilisateur a coupé les notifications de
    // discussion lui ferait manquer une réunion sans qu'il l'ait jamais demandé.
    final type = message.data['type'];
    if (type == 'meeting_invitation' || type == 'meeting_reminder') {
      final n = message.notification;
      showReunion(
        title: n?.title ?? 'Réunion',
        body: n?.body ?? '',
        meetingId: message.data['meetingId']?.toString(),
        payload: message.data,
      );
      return;
    }

    // Réglage : notifications de messages désactivées → on n'affiche rien.
    if (!notif.NotificationSettings.instance.messagesOn) return;

    final notification = message.notification;
    if (notification == null) return;

    final body = notif.NotificationSettings.instance.previewOn
        ? (notification.body ?? '')
        : 'Nouveau message';

    // Même construction que le chemin WebSocket, et surtout MÊME identité.
    //
    // L'ancien identifiant était horodaté, donc différent à chaque annonce :
    // le message arrivant par les deux canaux — WebSocket et push — produisait
    // deux notifications distinctes qui s'empilaient. Les faire porter le même
    // `convId` suffit : la seconde remplace la première.
    show(
      title: notification.title ?? 'Alanya',
      body: body,
      convId: message.data['convId']?.toString(),
      avatarUrl: message.data['avatarUrl']?.toString(),
      payload: message.data,
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
    // Rappel de localisation : on ouvre les réglages du système, seul endroit
    // où le GPS se rallume. Une navigation dans l'application n'y mènerait pas.
    if (data?['type'] == 'geo_rappel') {
      GeoService.instance.ouvrirReglagesLocalisation();
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
  /// Notification de message, au style « messagerie » d'Android.
  ///
  /// [convId] sert d'identité : deux annonces du même fil se REMPLACENT au lieu
  /// de s'empiler. C'est ce qui déduplique le WebSocket et le push, qui
  /// arrivent tous deux quand l'application est ouverte — et l'ancien `id = 0`
  /// faisait pire, en écrasant les fils entre eux.
  ///
  /// [avatarUrl] donne la pastille ronde de l'expéditeur. `MessagingStyle` est
  /// ce qu'Android offre de plus proche du bandeau interne de l'application :
  /// une notification système ne peut pas reproduire un widget Flutter, mais
  /// elle porte le même avatar, le même nom et la même couleur.
  Future<void> show({
    required String title,
    required String body,
    int id = 0,
    String? convId,
    String? avatarUrl,
    Map<String, dynamic>? payload,
  }) async {
    // Les deux API n'acceptent pas le même type pour la même image : `Person`
    // veut une icône, `largeIcon` une bitmap. On télécharge une seule fois.
    final octets = await _avatarPourNotification(avatarUrl);
    final avatar = octets == null ? null : ByteArrayAndroidBitmap(octets);
    final personne = Person(
      name: title,
      key: convId,
      icon: octets == null ? null : ByteArrayAndroidIcon(octets),
    );

    final details = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Notifications des nouveaux messages et appels',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFB85C38),
      sound: const RawResourceAndroidNotificationSound("notification"),
      playSound: true,
      largeIcon: avatar,
      // Regroupe les annonces d'un même fil, comme le bandeau le faisait.
      groupKey: convId,
      styleInformation: MessagingStyleInformation(
        personne,
        conversationTitle: title,
        messages: [
          Message(body, DateTime.now(), personne),
        ],
      ),
    );

    await _localPlugin.show(
      convId != null && convId.isNotEmpty ? convId.hashCode & 0x7fffffff : id,
      title,
      body,
      NotificationDetails(
        android: details,
        iOS: const DarwinNotificationDetails(),
      ),
      // `jsonEncode` et non `toString()` : le tap relit ce payload avec
      // `jsonDecode`, et la représentation Dart d'une Map n'est pas du JSON
      // (clés sans guillemets). Le chemin WebSocket produisait donc un payload
      // illisible, et toucher la notification n'ouvrait pas la conversation.
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  /// Notification de RÉUNION (invitation, rappel).
  ///
  /// Volontairement distincte de [show] : celle-ci est bâtie sur
  /// `MessagingStyle`, la mise en forme « conversation » d'Android, qui suppose
  /// un expéditeur et un fil. Une invitation n'est ni l'un ni l'autre, et
  /// s'afficherait comme un message reçu dans une discussion inexistante.
  ///
  /// Canal séparé (« Réunions ») pour que le son et l'importance restent
  /// réglables indépendamment des discussions dans les paramètres du système —
  /// Android ne sait pas les distinguer autrement.
  ///
  /// [meetingId] sert d'identité : deux annonces d'une même réunion se
  /// REMPLACENT au lieu de s'empiler, comme `convId` le fait pour les messages.
  Future<void> showReunion({
    required String title,
    required String body,
    String? meetingId,
    Map<String, dynamic>? payload,
  }) async {
    const details = AndroidNotificationDetails(
      'reunions',
      'Réunions',
      channelDescription: 'Invitations et rappels de réunion',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFB85C38),
      sound: RawResourceAndroidNotificationSound("notification"),
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );

    await _localPlugin.show(
      meetingId != null && meetingId.isNotEmpty
          ? "reunion-$meetingId".hashCode & 0x7fffffff
          : 0,
      title,
      body,
      const NotificationDetails(
        android: details,
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  /// Télécharge l'avatar pour la notification, ou renvoie `null`.
  ///
  /// Une notification ne doit jamais attendre le réseau : au-delà de trois
  /// secondes on s'en passe, l'annonce partant sans pastille plutôt qu'en
  /// retard — ou pas du tout.
  Future<Uint8List?> _avatarPourNotification(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
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
  // ⚠️ INDISPENSABLE AVANT TOUT APPEL DE PLUGIN. Cet isolate démarre nu :
  // sans ce réenregistrement, le premier plugin sollicité lève une
  // MissingPluginException qui interrompt TOUT le handler — donc plus aucune
  // notification d'appel, ni écran natif ni bandeau de repli.
  DartPluginRegistrant.ensureInitialized();
  debugPrint('[PushService] Message background: ${message.data['type']}');

  // Appel annulé/terminé par l'appelant → retire la notif d'appel plein écran
  // (ciblée par le callId partagé WS/FCM).
  if (message.data['type'] == 'call_cancelled') {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .cancel(PushService.callNotifId(message.data['callId']?.toString()));
    return;
  }

  // Appel entrant (app fermée/arrière-plan) → ÉCRAN d'appel natif.
  // Ne se déclenche que si le push est data-only (pas de bloc notification).
  if (message.data['type'] == 'incoming_call') {
    // Réglage : notifications d'appels désactivées → on n'affiche rien.
    if (!await notif.NotificationSettings.callsEnabledFresh()) return;

    final data = message.data;

    // Appel PÉRIMÉ : le serveur pose un TTL, mais un push déjà en transit peut
    // malgré tout arriver en retard — téléphone rallumé, réseau rétabli. Sans
    // ce contrôle, la sonnerie repartait pour un appel terminé depuis
    // longtemps, et l'annulation, envoyée avant, avait déjà été consommée.
    final envoiBrut = data['sentAt']?.toString();
    if (envoiBrut != null) {
      final envoi = DateTime.tryParse(envoiBrut);
      if (envoi != null &&
          DateTime.now().toUtc().difference(envoi.toUtc()) >
              const Duration(seconds: 90)) {
        debugPrint('[PushService] appel périmé ignoré (émis à $envoiBrut)');
        return;
      }
    }

    final callId = data['callId']?.toString();
    if (callId != null && callId.isNotEmpty) {
      // Vrai écran d'appel — avatar, nom, deux gros boutons — posé par-dessus
      // le verrouillage. Remplace le bandeau de texte que produisait
      // flutter_local_notifications, qui ne sait pas construire une
      // notification de style « appel ».
      try {
        await CallUiNative.afficherAppelEntrant(
          callId: callId,
          nom: data['callerName']?.toString() ?? 'Appel entrant',
          avatarUrl: data['callerAvatarUrl']?.toString(),
          video: data['callType'] == 'VIDEO',
        );
        return;
      } catch (e) {
        // ⚠️ NE PAS LAISSER REMONTER. Un échec ici — plugin indisponible,
        // constructeur récalcitrant — faisait disparaître l'appel entrant sans
        // aucune trace : l'exception interrompait le handler avant le repli.
        // Mieux vaut un bandeau ordinaire qu'un appel jamais signalé.
        debugPrint('[PushService] écran d\'appel natif indisponible: $e');
      }
    }

    // Repli : écran natif indisponible, ou push sans identifiant d'appel —
    // celui-ci ne pourrait alors être ni refermé ni rattaché à un appel. On
    // retombe sur l'ancienne notification, moins belle mais qui prévient.
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
Future<void> notificationBackgroundHandler(
    NotificationResponse response) async {
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

  await refuserAppelDepuisIsolate(callId);
}

/// Refus déclenché depuis l'ÉCRAN D'APPEL NATIF, application en arrière-plan
/// ou TUÉE.
///
/// L'écouteur `FlutterCallkitIncoming.onEvent` de `CallListener` vit dans un
/// widget : application tuée, il n'existe pas. Refuser depuis l'écran natif
/// n'ouvre pas l'application — personne n'écoutait donc l'événement, et le
/// serveur n'apprenait jamais le refus. L'appelant continuait de sonner
/// jusqu'au minuteur des 90 s alors que son correspondant avait dit non.
///
/// C'est le chemin que le paquet prévoit exactement pour ce cas
/// (`onBackgroundMessage`, « background or terminated ») : le pendant Dart du
/// POST natif que fait le modèle de référence depuis Kotlin.
///
/// Le délai de sonnerie compte comme un refus, pour la même raison qu'au
/// premier plan : mieux vaut que l'appelant cesse de sonner tout de suite.
@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  final String? callId = switch (event) {
    CallEventActionCallDecline(:final callKitParams) => callKitParams.id,
    CallEventActionCallTimeout(:final id) => id,
    _ => null,
  };
  if (callId == null || callId.isEmpty) return;

  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  await refuserAppelDepuisIsolate(callId);
}

/// Prévient le serveur qu'un appel est refusé, depuis un isolate SANS INTERFACE.
///
/// Partagée par les deux chemins d'arrière-plan — la notification locale et
/// l'écran d'appel natif — parce que la difficulté est la même dans les deux
/// cas : aucun état en mémoire, aucun `ApiClient`, et un jeton d'accès qui a
/// toutes les chances d'être périmé.
@pragma('vm:entry-point')
Future<void> refuserAppelDepuisIsolate(String callId) async {
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

/// Le greffon de notifications, vu depuis un isolate SANS INTERFACE.
///
/// ⚠️ `PushService.instance` n'est PAS utilisable ici : son `_localPlugin` a été
/// initialisé dans l'isolate de l'application, et un isolate ne partage aucune
/// mémoire avec un autre. Il faut donc une instance neuve, initialisée sur
/// place — même famille que le repli de `notificationBackgroundHandler`.
Future<FlutterLocalNotificationsPlugin> _greffonPourIsolate() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ));
  return plugin;
}

/// Repose le rappel de localisation depuis le service de premier plan.
///
/// C'est CE QUI TIENT LA PROMESSE quand l'application est fermée : la veille de
/// `GeoService` vit dans l'isolate de l'application, qu'Android détruit dès que
/// l'utilisateur balaie l'application des tâches récentes. Sans ce relais, un
/// rappel balayé sur Android 14 ne reviendrait qu'au prochain lancement.
@pragma('vm:entry-point')
Future<void> montreRappelLocalisationDepuisIsolate() async {
  try {
    final plugin = await _greffonPourIsolate();
    await plugin.show(
      PushService.idRappelLocalisation,
      PushService.titreRappelLocalisation,
      PushService.texteRappelLocalisation,
      PushService.detailsRappelLocalisation(permanent: true),
      payload: PushService.payloadRappelLocalisation,
    );
  } catch (e) {
    debugPrint('[PushService] rappel hors application impossible : $e');
  }
}

/// Retire le rappel depuis le service de premier plan.
///
/// ⚠️ INDISPENSABLE, et pas seulement symétrique : une notification non
/// balayable ne part que par du code. Si seule l'application savait la retirer,
/// quelqu'un qui rallume sa localisation sans rouvrir Alanya garderait sous les
/// yeux, indéfiniment, l'annonce d'un problème déjà résolu.
@pragma('vm:entry-point')
Future<void> retireRappelLocalisationDepuisIsolate() async {
  try {
    final plugin = await _greffonPourIsolate();
    await plugin.cancel(PushService.idRappelLocalisation);
  } catch (_) {}
}
