import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Connexion WebRTC vers un seul pair (utilisée par le mesh de groupe).
class WebrtcPeerSession {
  WebrtcPeerSession({
    required this.peerId,
    required this.isVideo,
    required this.isOfferer,
    required this.localStream,
    required this.iceServers,
    required this.onSendSignal,
    required this.onUpdated,
  });

  final String peerId;
  final bool isVideo;
  final bool isOfferer;
  final MediaStream localStream;
  final List<Map<String, dynamic>> iceServers;
  final void Function(Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;

  RTCPeerConnection? _pc;
  MediaStream? _remote;
  bool _started = false;

  /// Vrai seulement quand la session peut RÉELLEMENT traiter un signal :
  /// `_pc` créé ET pistes locales ajoutées.
  ///
  /// À ne pas confondre avec `_started`, qui marque l'entrée dans `start()`.
  /// Entre les deux il y a plusieurs `await` (création de la connexion,
  /// résolution des serveurs ICE, ajout des pistes) pendant lesquels des
  /// signaux arrivent : le WebSocket appelle `handleSignal` sans l'attendre,
  /// et le mesh publie la session dans `_peers` AVANT d'appeler `start()`.
  /// Se fier à `_started` faisait passer ces signaux dans `_applySignal` avec
  /// `_pc` encore nul : l'offre était jetée en silence, aucune answer n'était
  /// produite, et l'appel restait « Connexion en cours… » jusqu'à l'échec.
  bool _ready = false;
  bool _remoteReady = false;
  final _pendingSignals = <Map<String, dynamic>>[];
  final _iceQueue = <RTCIceCandidate>[];

  MediaStream? get remoteStream => _remote;
  bool get mediaConnected => _remote != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final raw = iceServers.isNotEmpty ? iceServers : WebrtcPeerSession.fallbackIce;
    final servers = normalizeIceServers(raw);
    // Configuration WebRTC :
    //  - iceTransportPolicy: "all"  → essaie d'abord P2P direct, puis relay TURN
    //  - bundlePolicy: "max-bundle" → 1 seul port UDP pour tous les médias
    //                                  (obligatoire pour beaucoup de firewalls)
    //  - rtcpMuxPolicy: "require"   → RTP + RTCP sur le même port
    //  - sdpSemantics: "unified-plan" → format SDP moderne (requis flutter_webrtc récent)
    _pc = await createPeerConnection({
      "iceServers": servers,
      "iceTransportPolicy": "all",
      "bundlePolicy": "max-bundle",
      "rtcpMuxPolicy": "require",
      "sdpSemantics": "unified-plan",
    });
    _pc!.onIceCandidate = (RTCIceCandidate? c) {
      if (c == null) return;
      final preview = c.candidate ?? "";
      debugPrint("[webrtc/$peerId] ICE candidate: ${preview.length > 80 ? preview.substring(0, 80) : preview}");
      onSendSignal({"kind": "ice", "candidate": c.toMap()});
    };
    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint("[webrtc/$peerId] ICE state: $state");
    };
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint("[webrtc/$peerId] Connection state: $state");
    };
    _pc!.onTrack = (RTCTrackEvent e) {
      debugPrint("[webrtc/$peerId] ⬇️ onTrack: kind=${e.track.kind} streams=${e.streams.length}");
      if (e.streams.isNotEmpty) {
        _remote = e.streams.first;
        onUpdated();
      }
    };

    for (final track in localStream.getTracks()) {
      await _pc!.addTrack(track, localStream);
    }

    if (isOfferer) {
      await _createOffer();
    }

    // La session n'est déclarée prête qu'ici : les pistes locales sont posées,
    // donc l'answer produite en réponse à une offre en attente portera bien le
    // média. Ouvrir plus tôt renverrait une answer sans piste.
    _ready = true;
    await _flushPendingSignals();
  }

  // Serveurs ICE (STUN + TURN) pour la traversée NAT.
  //
  // STRUCTURE IMPORTANTE : chaque entrée doit avoir UN SEUL "urls" avec UN SEUL
  // protocole. Mélanger stun: et turn: dans un même objet ICEServer avec
  // username/credential est mal supporté par plusieurs implémentations WebRTC
  // (les credentials seraient appliquées au stun: aussi, ce qui trouble le stack).
  //
  // On propose plusieurs transports pour maximiser les chances de succès sur
  // réseaux mobiles restrictifs (4G Cameroun, WiFi d'entreprise, etc.) :
  //   1. STUN UDP alanya  : le plus rapide, résout la plupart des NATs
  //   2. STUN Google      : backup public au cas où alanya.cloud momentanément KO
  //   3. TURN UDP         : relay si STUN insuffisant (NAT symétrique)
  //   4. TURN TCP         : fallback si UDP entièrement bloqué
  //   5. TURNS 443        : dernier recours, passe même derrière les proxies HTTPS
  // Fallback utilisé UNIQUEMENT si /api/calls/ice échoue. Domaines corrigés
  // (les anciens "alanya2.cloud" / "google2.com" n'existaient pas → ENOTFOUND).
  // NB : les identifiants TURN statiques ci-dessous ne fonctionnent que si le
  // Coturn accepte aussi une auth statique ; sinon seuls les STUN servent de
  // secours. Le vrai chemin TURN passe par /api/calls/ice (HMAC).
  static const fallbackIce = [
    {"urls": "stun:stun.l.google.com:19302"},
    {"urls": "stun:stun1.l.google.com:19302"},
    {"urls": "stun:open.alanya.cloud:3478"},
    {
      "urls": "turn:open.alanya.cloud:3478?transport=udp",
      "username": "alanya",
      "credential": "alanya2026",
    },
    {
      "urls": "turn:open.alanya.cloud:3478?transport=tcp",
      "username": "alanya",
      "credential": "alanya2026",
    },
    {
      "urls": "turns:open.alanya.cloud:5349?transport=tcp",
      "username": "alanya",
      "credential": "alanya2026",
    },
  ];
  /// Normalise la liste ICE avant de la passer à WebRTC :
  ///  - éclate un objet à `urls` multiples en une entrée par URL,
  ///  - ne met les identifiants que sur TURN/TURNS (jamais sur STUN).
  /// Corrige le format « bundlé » renvoyé par certaines sources (dont l'ancien
  /// /api/calls/ice) qui casse le TURN sur flutter_webrtc.
  static List<Map<String, dynamic>> normalizeIceServers(
    List<Map<String, dynamic>> input,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final s in input) {
      final urlsRaw = s["urls"];
      final username = s["username"];
      final credential = s["credential"];
      final urls = urlsRaw is List ? urlsRaw : [urlsRaw];
      for (final u in urls) {
        if (u == null) continue;
        final url = u.toString();
        final isStun = url.startsWith("stun:");
        final entry = <String, dynamic>{"urls": url};
        if (!isStun && username != null) entry["username"] = username;
        if (!isStun && credential != null) entry["credential"] = credential;
        out.add(entry);
      }
    }
    return out;
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (!_ready) {
      _pendingSignals.add(signal);
      return;
    }
    await _applySignal(signal);
  }

  Future<void> _createOffer() async {
    final pc = _pc;
    if (pc == null) return;
    final offer = await pc.createOffer({
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": isVideo,
      },
      "optional": [],
    });
    await pc.setLocalDescription(offer);
    onSendSignal({"kind": "offer", "sdp": offer.sdp, "type": offer.type});
  }

  Future<void> _applySignal(Map<String, dynamic> signal) async {
    final pc = _pc;
    // Ceinture et bretelles : plus aucun signal ne doit être perdu en silence.
    // S'il arrive alors que la connexion n'existe pas (ou plus), il retourne
    // dans la file — `_flushPendingSignals` le rejouera quand elle sera prête.
    if (pc == null) {
      _pendingSignals.add(signal);
      return;
    }
    final kind = signal["kind"] as String?;

    if (kind == "offer") {
      final sdp = signal["sdp"] as String?;
      if (sdp == null) return;
      final type = signal["type"] as String? ?? "offer";
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteReady = true;
      await _flushIceQueue();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      onSendSignal({"kind": "answer", "sdp": answer.sdp, "type": answer.type});
    } else if (kind == "answer") {
      final sdp = signal["sdp"] as String?;
      if (sdp == null) return;
      final type = signal["type"] as String? ?? "answer";
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteReady = true;
      await _flushIceQueue();
    } else if (kind == "ice") {
      final raw = signal["candidate"];
      if (raw is! Map) return;
      final cand = RTCIceCandidate(
        raw["candidate"] as String?,
        raw["sdpMid"] as String?,
        raw["sdpMLineIndex"] as int?,
      );
      if (_remoteReady) {
        await pc.addCandidate(cand);
      } else {
        _iceQueue.add(cand);
      }
    }
  }

  Future<void> _flushPendingSignals() async {
    final copy = List<Map<String, dynamic>>.from(_pendingSignals);
    _pendingSignals.clear();
    for (final s in copy) {
      await _applySignal(s);
    }
  }

  Future<void> _flushIceQueue() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in List<RTCIceCandidate>.from(_iceQueue)) {
      await pc.addCandidate(c);
    }
    _iceQueue.clear();
  }

  Future<void> close() async {
    _remote = null;
    await _pc?.close();
    _pc = null;
    _started = false;
    _ready = false;
    _remoteReady = false;
    _pendingSignals.clear();
    _iceQueue.clear();
  }
}
