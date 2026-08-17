import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'debug_overlay.dart';
import 'device_registry.dart';
import 'server_config.dart';
import 'token_storage.dart';

/// Client WebSocket temps réel : connexion authentifiée, reconnexion auto,
/// flux d'événements diffusé et envoi de messages / accusés / « typing ».
class RealtimeClient extends ChangeNotifier {
  RealtimeClient(this._storage, {String? wsUrl})
      : _wsUrl = wsUrl ?? _defaultWsUrl;

  final TokenStorage _storage;
  final String _wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _connecting = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  bool connected = false;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _controller.stream;

  static String get _defaultWsUrl => ServerConfig.wsBase;

  Future<void> connect() async {
    if (_disposed || _connecting || connected) return;
    _connecting = true;
    final token = await _storage.accessToken;
    if (token == null) {
      _connecting = false;
      return;
    }
    // FIX perf DNS : sur mobile, le premier lookup DNS d'un domaine peut échouer
    // (cache négatif de l'opérateur) puis marcher 30s plus tard. On préchauffe
    // le DNS via un GET HEAD léger sur l'hôte WS AVANT la tentative WSS.
    // Ça ne coûte que quelques ms si le DNS est déjà chaud.
    await _warmupDns();
    try {
      DebugOverlay.log("WS → connexion à $_wsUrl");
      final channel =
          WebSocketChannel.connect(Uri.parse("$_wsUrl?token=$token"));
      await channel.ready; // lève une exception si la connexion échoue
      _channel = channel;
      _connecting = false;
      _setConnected(true);
      DebugOverlay.log("WS ✅ CONNECTÉ");
      _reconnectAttempt = 0;

      // Annonce de l'appareil, avant tout le reste.
      //
      // Le serveur doit savoir quelle socket appartient à quel poste : c'est ce
      // qui lui permet de ne faire sonner que le détenteur d'une conversation
      // réservée. Sans cette annonce, il ne peut identifier personne et fait
      // sonner tous les appareils du compte — le repli qui existe côté serveur
      // n'est là que tant que ce message manque.
      //
      // Renvoyé à CHAQUE connexion : une socket neuve ne porte aucune identité.
      unawaited(_annoncerAppareil());

      _sub = channel.stream.listen(
        _onData,
        onDone: _handleDrop,
        onError: (e) {
          DebugOverlay.log("WS ⚠️ err: $e");
          _handleDrop();
        },
        // FIX: cancelOnError:false — sinon la moindre trame louche tue la sub
        // et on rate tous les incoming_call qui suivent.
        cancelOnError: false,
      );
      // Ping applicatif toutes les 20s pour maintenir la connexion vivante
      // à travers les NAT mobiles agressifs (opérateurs qui killent les TCP idle).
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          _channel?.sink.add(jsonEncode({"type": "ping"}));
          // Rattrapage : l'enregistrement de l'appareil peut se terminer APRÈS
          // l'ouverture de la socket. Tant que l'identité n'est pas connue, on
          // retente à chaque ping — une fois annoncée, la condition ne coûte
          // plus rien.
          if (_appareilId == null) unawaited(_annoncerAppareil());
        } catch (_) {}
      });
    } catch (e) {
      DebugOverlay.log("WS ❌ échec: $e");
      _connecting = false;
      _setConnected(false);
      // FIX: on détecte les erreurs DNS pour retenter plus vite qu'un vrai
      // refus TCP. Un cache DNS négatif se rafraîchit en général en <10s.
      final isDnsError = e.toString().contains("Failed host lookup") ||
          e.toString().contains("errno = 7");
      _scheduleReconnect(dnsError: isDnsError);
    }
  }

  /// Préchauffe le DNS en tentant une résolution silencieuse de l'hôte WS
  /// via une requête HTTP HEAD très courte. Bypass des caches négatifs
  /// opérateur constatés au Cameroun sur les nouveaux sous-domaines Cloudflare.
  Future<void> _warmupDns() async {
    try {
      final uri = Uri.parse(_wsUrl.replaceFirst(RegExp(r'^wss?'), 'https'));
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req = await client.headUrl(uri).timeout(const Duration(seconds: 3));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      // On draine et ferme, on se moque du statut (426 attendu pour un WS pur).
      await resp.drain<void>();
      client.close(force: true);
    } catch (_) {
      // Si le warmup échoue, on tente quand même la WS ensuite : peut-être que
      // le driver WebSocket a un résolveur DNS différent qui, lui, marchera.
    }
  }

  void _onData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is Map<String, dynamic>) {
        final type = decoded["type"];
        DebugOverlay.log("WS ⬇️ $type");
        if (type == "incoming_call") {
          DebugOverlay.log("📞 INCOMING_CALL reçu !");
          debugPrint("[RealtimeClient] Trame incoming_call reçue du serveur !");
        }
        _controller.add(decoded);
      } else {
        DebugOverlay.log("WS ⬇️ (non-map)");
      }
    } catch (e) {
      DebugOverlay.log("WS ⬇️ ❌ non-JSON: $e");
    }
  }

  void _handleDrop() {
    DebugOverlay.log("WS 🔌 déconnecté (drop)");
    _setConnected(false);
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect({bool dnsError = false}) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // FIX perf : backoff distinct selon le type d'erreur.
    // - DNS négatif (cache opérateur) : retry rapide 1→2→3→5→8→15s. Le cache
    //   se rafraîchit en général en <10s côté opérateur mobile.
    // - Autre (TCP refused, timeout) : backoff plus prudent 2→4→8→16→30s
    //   pour ne pas saturer un serveur qui redémarre.
    const dnsSequence = [1, 2, 3, 5, 8, 15, 30];
    const tcpSequence = [2, 4, 8, 16, 30, 30];
    final seq = dnsError ? dnsSequence : tcpSequence;
    final delaySec = seq[_reconnectAttempt.clamp(0, seq.length - 1)];
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, seq.length - 1);
    DebugOverlay.log(
        "WS ⏳ reconnexion dans ${delaySec}s ${dnsError ? "(DNS)" : ""}");
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }

  void _setConnected(bool v) {
    if (connected == v) return;
    connected = v;
    notifyListeners();
    // Émis dans le flux d'événements, et pas seulement via notifyListeners :
    // les écrans écoutent déjà ce flux pour `message`, `call_state`… et
    // peuvent donc traiter la reconnexion comme un événement de plus, sans
    // brancher un second mécanisme.
    //
    // À QUOI ÇA SERT — un événement WebSocket n'est jamais rejoué. Tout ce qui
    // s'est produit pendant que la connexion était tombée (un appel manqué,
    // typiquement, puisqu'on n'était justement pas là) n'arrivera jamais. La
    // reconnexion est le seul moment où l'on sait qu'un trou vient de se
    // refermer : c'est là qu'il faut rattraper l'état par une requête HTTP.
    if (v && !_disposed && !_controller.isClosed) {
      // AVANT de prévenir les écrans : une trame d'appel restée en attente doit
      // partir en premier, sinon l'appelant apprend l'état trop tard.
      _videLaFile();
      _controller.add({"type": "ws_connected"});
    }
  }

  /// Trames de SIGNALISATION D'APPEL mises en attente si la connexion n'est pas
  /// encore établie.
  ///
  /// ⚠️ POURQUOI SEULEMENT CELLES-LÀ. Rejouer un « est en train d'écrire » vieux
  /// de dix secondes n'aurait aucun sens ; perdre un « j'ai décroché » casse
  /// l'appel. Ces trois types décident de l'état d'un appel des DEUX côtés :
  /// ils doivent arriver, même en retard.
  static const _typesCritiques = {
    "call_state",
    "call_ring",
    "call_signal",
    // call_invite est critique : s'il est perdu sur une coupure réseau, une
    // invitation de transfert n'atteint jamais la cible et l'initiateur attend
    // indéfiniment que la cible rejoigne.
    "call_invite",
    // Une éviction perdue laisse l'appareil sortant connecté jusqu'à
    // l'expiration de son jeton d'accès, soit un quart d'heure. Elle part
    // justement au moment le plus défavorable : la socket vient d'être ouverte
    // par une connexion toute fraîche.
    "session_revoked",
    "meeting_join",
    "meeting_leave",
    "meeting_signal",
    // Perdue, une prolongation laisse TOUTE la salle sur une durée périmée et
    // en alerte de dépassement — l'organisateur croit l'avoir accordée.
    "meeting_extend",
  };

  final List<({Map<String, dynamic> payload, DateTime expire})> _enAttente = [];

  /// Dernier identifiant connu, pour réannoncer sans repasser par le disque.
  int? _appareilId;

  /// Annonce l'appareil courant, si on le connaît déjà.
  Future<void> _annoncerAppareil() async {
    final id = _appareilId ?? await DeviceRegistry.instance.appareilId();
    if (id == null) return;
    _appareilId = id;
    _send({"type": "device", "appareilId": id});
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || !connected) {
      // ⚠️ CE CHEMIN ÉTAIT UN `return` MUET, et c'est ce qui cassait
      // l'acceptation depuis la notification : décrocher DÉMARRE
      // l'application, donc le « joined » partait avant que la connexion ne
      // soit ouverte. La trame disparaissait, l'appelant n'apprenait jamais que
      // son correspondant avait décroché — il continuait de sonner pendant que
      // l'autre restait sur « connexion en cours ».
      if (_typesCritiques.contains(payload["type"])) {
        // 30 s : au-delà, l'appel est de toute façon terminé côté serveur, et
        // rejouer une trame périmée ferait plus de mal que de bien.
        _enAttente.add((
          payload: payload,
          expire: DateTime.now().add(const Duration(seconds: 30)),
        ));
        DebugOverlay.log("WS ⏸️ ${payload["type"]} en attente de connexion");
      }
      return;
    }
    ch.sink.add(jsonEncode(payload));
  }

  /// Vide la file dès que la connexion est là. Les trames périmées sont
  /// écartées plutôt qu'envoyées.
  void _videLaFile() {
    if (_enAttente.isEmpty) return;
    final maintenant = DateTime.now();
    final aEnvoyer =
        _enAttente.where((e) => e.expire.isAfter(maintenant)).toList();
    _enAttente.clear();
    final ch = _channel;
    if (ch == null || !connected) return;
    for (final e in aEnvoyer) {
      try {
        ch.sink.add(jsonEncode(e.payload));
        DebugOverlay.log("WS ▶️ ${e.payload["type"]} envoyé après reconnexion");
      } catch (_) {}
    }
  }

  void sendMessage(String convId, String content, String tempId,
          {String? replyToId}) =>
      _send({
        "type": "send",
        "convId": convId,
        "content": content,
        "msgType": "TEXT",
        "tempId": tempId,
        if (replyToId != null) "replyToId": replyToId,
      });

  void sendMedia(String convId, String mediaId, String msgType, String tempId,
          {String? replyToId, String? content}) =>
      _send({
        "type": "send",
        "convId": convId,
        "mediaId": mediaId,
        "msgType": msgType,
        "tempId": tempId,
        if (content != null && content.isNotEmpty) "content": content,
        if (replyToId != null) "replyToId": replyToId,
      });

  void sendMultiMedia(
          String convId, List<String> mediaIds, String msgType, String tempId,
          {String? replyToId, String? content}) =>
      _send({
        "type": "send",
        "convId": convId,
        "mediaIds": mediaIds,
        "msgType": msgType,
        "tempId": tempId,
        if (content != null && content.isNotEmpty) "content": content,
        if (replyToId != null) "replyToId": replyToId,
      });

  /// Message dont la charge utile vit dans `content` : `CONTACT`, `LOCATION`.
  ///
  /// Le média est FACULTATIF ici, contrairement à [sendMedia] : la photo d'un
  /// contact du répertoire en est un, une position n'en a jamais. Le serveur
  /// refuse la trame si la charge ne respecte pas le format partagé — voir
  /// `models/message_payload.dart` et son miroir `src/lib/message-payload.mjs`.
  void sendStructured(
          String convId, String msgType, String content, String tempId,
          {String? mediaId, String? replyToId}) =>
      _send({
        "type": "send",
        "convId": convId,
        "content": content,
        "msgType": msgType,
        "tempId": tempId,
        if (mediaId != null) "mediaId": mediaId,
        if (replyToId != null) "replyToId": replyToId,
      });

  void markRead(String convId) => _send({"type": "read", "convId": convId});

  /// Annonce aux autres sessions du compte qu'un appareil vient d'être
  /// déconnecté, pour qu'elles réagissent sans attendre l'expiration du jeton
  /// d'accès (15 minutes).
  ///
  /// Le serveur ne rediffuse qu'aux sockets du même compte : on ne peut couper
  /// que ses propres appareils.
  /// [raison] `"eviction"` quand c'est une connexion ailleurs qui ferme cette
  /// session, absente quand l'utilisateur déconnecte lui-même un poste depuis
  /// « Appareils connectés ». L'appareil visé s'en sert pour dire la vérité.
  void sendSessionRevoked(String deviceId, {String? raison}) => _send({
        "type": "session_revoked",
        "deviceId": deviceId,
        if (raison != null) "raison": raison,
      });

  /// Réaction emoji sur un message. `emoji` vide = retrait ; renvoyer le même
  /// emoji que l'actuel = bascule (retrait) côté serveur.
  void sendReaction(String convId, String messageId, String emoji) => _send({
        "type": "reaction",
        "convId": convId,
        "messageId": messageId,
        "emoji": emoji,
      });

  void deleteMessage(String messageId, {String scope = "me"}) =>
      _send({"type": "delete_message", "messageId": messageId, "scope": scope});

  /// Modifier le contenu d'un message texte (seul l'expéditeur, côté serveur).
  void editMessage(String messageId, String content) => _send(
      {"type": "edit_message", "messageId": messageId, "content": content});

  /// Épingler (messageId) ou détacher (null) un message dans une conversation.
  void pinMessage(String convId, String? messageId) =>
      _send({"type": "pin_message", "convId": convId, "messageId": messageId});

  /// Règle le minuteur des messages éphémères (secondes, 0 = désactivé).
  void setDisappearing(String convId, int seconds) =>
      _send({"type": "set_disappearing", "convId": convId, "seconds": seconds});

  void forwardMessage(String messageId, List<String> targetConvIds) => _send({
        "type": "forward_message",
        "messageId": messageId,
        "targetConvIds": targetConvIds
      });

  void sendTyping(String convId, bool isTyping) =>
      _send({"type": "typing", "convId": convId, "isTyping": isTyping});

  void sendRecording(String convId, bool isRecording) => _send(
      {"type": "recording", "convId": convId, "isRecording": isRecording});

  void callRing(String callId) =>
      _send({"type": "call_ring", "callId": callId});

  void callSignal(
          String callId, String toUserId, Map<String, dynamic> signal) =>
      _send({
        "type": "call_signal",
        "callId": callId,
        "toUserId": toUserId,
        "signal": signal
      });

  void callState(
    String callId,
    String state, {
    String? userId,
    String? displayName,
  }) =>
      _send({
        "type": "call_state",
        "callId": callId,
        "state": state,
        if (userId != null) "userId": userId,
        if (displayName != null) "displayName": displayName,
      });

  /// Invite un utilisateur (par son numéro public) dans un appel en cours.
  void callInvite(String callId, String publicNumber) => _send({
        "type": "call_invite",
        "callId": callId,
        "publicNumber": publicNumber,
      });

  /// Touche tapée dans le menu d'un standard (centre d'appels).
  ///
  /// ⚠️ VOLONTAIREMENT ABSENTE de [_typesCritiques]. Rejouer une touche après
  /// une reconnexion ferait sonner un agent pour un appelant qui n'est peut-être
  /// plus là — le serveur referme la session dès que sa socket tombe. Une touche
  /// perdue se retape ; une touche rejouée dérange quelqu'un pour rien.
  void ivrDtmf(String callId, int digit) =>
      _send({"type": "ivr_dtmf", "callId": callId, "digit": digit});

  void meetingJoin(int meetingId) =>
      _send({"type": "meeting_join", "meetingId": meetingId});

  void meetingLeave(int meetingId) =>
      _send({"type": "meeting_leave", "meetingId": meetingId});

  /// Prolonge la durée prévue d'une réunion (organisateur seul, contrôlé par le
  /// serveur). [dureeSec] est la NOUVELLE durée totale, pas le supplément.
  void meetingExtend(int meetingId, int dureeSec) => _send({
        "type": "meeting_extend",
        "meetingId": meetingId,
        "duree": dureeSec,
      });

  void meetingSignal(
          int meetingId, String toUserId, Map<String, dynamic> signal) =>
      _send({
        "type": "meeting_signal",
        "meetingId": meetingId,
        "toUserId": toUserId,
        "signal": signal,
      });

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
    /*
     * ⚠️ VIDER LA FILE, ET C'EST ICI QUE ÇA COMPTE.
     *
     * Les trames en attente appartiennent à la session qui se termine, mais le
     * serveur les attribue à `ws.userId` — c'est-à-dire à qui tient la socket au
     * moment où elles partent. Sans cette purge, A se déconnecte, B se connecte
     * sur le même téléphone dans les trente secondes, et `_videLaFile()` rejoue
     * sur la socket de B des trames décidées par A : un « j'ai décroché », un
     * « je quitte l'appel », une éviction d'appareil. Même famille de bug que le
     * message de B qui partait au nom de A, et qui venait d'un WebSocket resté
     * ouvert avec le jeton du précédent.
     *
     * `disconnect()` n'est appelé qu'à la FIN D'UNE SESSION — les coupures
     * réseau passent par `_handleDrop`, qui laisse la file intacte. La purge ne
     * retire donc jamais une trame qu'une reconnexion devait porter.
     */
    _enAttente.clear();
    _setConnected(false);
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _controller.close();
    super.dispose();
  }
}
