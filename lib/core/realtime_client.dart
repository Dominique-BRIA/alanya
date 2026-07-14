import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'debug_overlay.dart';
import 'server_config.dart';
import 'token_storage.dart';

/// Client WebSocket temps réel : connexion authentifiée, reconnexion auto,
/// flux d'événements diffusé et envoi de messages / accusés / « typing ».
class RealtimeClient extends ChangeNotifier {
  RealtimeClient(this._storage, {String? wsUrl}) : _wsUrl = wsUrl ?? _defaultWsUrl;

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
      final channel = WebSocketChannel.connect(Uri.parse("$_wsUrl?token=$token"));
      await channel.ready; // lève une exception si la connexion échoue
      _channel = channel;
      _connecting = false;
      _setConnected(true);
      DebugOverlay.log("WS ✅ CONNECTÉ");
      _reconnectAttempt = 0;
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
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
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
    DebugOverlay.log("WS ⏳ reconnexion dans ${delaySec}s ${dnsError ? "(DNS)" : ""}");
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }

  void _setConnected(bool v) {
    if (connected == v) return;
    connected = v;
    notifyListeners();
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || !connected) return;
    ch.sink.add(jsonEncode(payload));
  }

  void sendMessage(String convId, String content, String tempId, {String? replyToId}) =>
      _send({
        "type": "send",
        "convId": convId,
        "content": content,
        "msgType": "TEXT",
        "tempId": tempId,
        if (replyToId != null) "replyToId": replyToId,
      });

  void sendMedia(String convId, String mediaId, String msgType, String tempId, {String? replyToId}) => _send({
        "type": "send",
        "convId": convId,
        "mediaId": mediaId,
        "msgType": msgType,
        "tempId": tempId,
        if (replyToId != null) "replyToId": replyToId,
      });

  void markRead(String convId) => _send({"type": "read", "convId": convId});

  void deleteMessage(String messageId, {String scope = "me"}) =>
      _send({"type": "delete_message", "messageId": messageId, "scope": scope});

  void forwardMessage(String messageId, List<String> targetConvIds) =>
      _send({"type": "forward_message", "messageId": messageId, "targetConvIds": targetConvIds});

  void sendTyping(String convId, bool isTyping) =>
      _send({"type": "typing", "convId": convId, "isTyping": isTyping});

  void callRing(String callId) => _send({"type": "call_ring", "callId": callId});

  void callSignal(String callId, String toUserId, Map<String, dynamic> signal) =>
      _send({"type": "call_signal", "callId": callId, "toUserId": toUserId, "signal": signal});

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

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
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
