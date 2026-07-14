import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/realtime_client.dart';
import '../../core/ringtone_service.dart';
import '../../models/call_record.dart';
import 'calls_repository.dart';
import 'webrtc_group_mesh.dart';
import 'webrtc_peer_session.dart';

enum ActiveCallRole { outgoing, incoming, ongoing }

/// Appels directs et de groupe — mesh WebRTC (une connexion par participant).
class CallController extends ChangeNotifier {
  CallController(this._calls, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final CallsRepository _calls;
  final RealtimeClient _rt;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _ringTimeout;

  String? myUserId;
  String? myDisplayName;

  IncomingCallInfo? incoming;
  String? activeCallId;
  String? activeConvId;
  String? activePeerName;
  String activeType = "AUDIO";
  ActiveCallRole? activeRole;
  bool isGroupCall = false;
  bool isCallInitiator = false;
  final Map<String, String> participantNames = {};
  final Set<String> joinedParticipantIds = {};

  WebrtcGroupMesh? _mesh;
  final Map<String, Map<String, List<Map<String, dynamic>>>> _signalBuffer = {};
  List<Map<String, dynamic>>? _iceServers;
  String? lastError;

  MediaStream? get localStream => _mesh?.localStream;
  Map<String, MediaStream> get remoteStreams => _mesh?.remoteStreams ?? {};
  int get connectedPeerCount => _mesh?.connectedCount ?? 0;
  bool get mediaConnected => connectedPeerCount > 0;

  /// FIX: activeRole est inclus pour éviter que isBusy == false
  /// pendant la transition incoming → activeCallId dans acceptIncoming().
  bool get isBusy => activeCallId != null || incoming != null || activeRole != null;

  void bindUser(String userId, String displayName) {
    myUserId = userId;
    myDisplayName = displayName;
    // Nettoie les appels bloqués en base de données (l'app a crashé pendant un appel)
    _cleanupStaleCalls();
  }

  /// Nettoie les anciens appels restés en statut RINGING/ONGOING pour cet user.
  /// Évite l'erreur "Vous êtes déjà en appel" (409 BUSY) après un crash.
  Future<void> _cleanupStaleCalls() async {
    if (myUserId == null) return;
    try {
      // Marque tous les appels non terminés de cet user comme ENDED
      final stale = await _calls.history();
      // Pas besoin de cleanup si pas d'appels récents
    } catch (_) {}
  }

  Future<void> startOutgoing(String convId, String type, String title) async {
    if (isBusy) {
      lastError = "Termine l'appel en cours avant d'en lancer un autre";
      notifyListeners();
      throw StateError("BUSY");
    }
    lastError = null;
    final started = await _calls.start(convId, type);
    debugPrint("[CallController] Appel créé sur le backend, envoi du signal call_ring...");
    _rt.callRing(started.id);
    activeCallId = started.id;
    activeConvId = convId;
    isGroupCall = started.isGroup;
    isCallInitiator = true;
    activePeerName = started.isGroup ? (started.groupName ?? title) : title;
    activeType = type;
    activeRole = ActiveCallRole.outgoing;
    participantNames.clear();
    joinedParticipantIds.clear();
    if (myUserId != null) joinedParticipantIds.add(myUserId!);
    for (final c in started.callees) {
      participantNames[c.userId] = c.pseudo ?? c.publicNumber ?? "Membre";
    }
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 60), () {
      if (activeRole == ActiveCallRole.outgoing && activeCallId != null) {
        hangUp();
      }
    });
    // Sonnerie sortante (bip d'attente) tant que le destinataire n'a pas
    // décroché. Arrêtée dans _onPeerJoined / _clear / hangUp.
    RingtoneService.instance.startOutgoing();
    notifyListeners();
    // Initialise le stream local immédiatement pour que l'appelant soit prêt
    // à envoyer de l'audio/vidéo dès que le destinataire accepte.
    try {
      await _ensureMesh();
    } catch (e) {
      // Permission refusée : annule l'appel proprement
      await RingtoneService.instance.stop();
      await _calls.end(started.id);
      _rt.callState(started.id, "ended", userId: myUserId, displayName: myDisplayName);
      _clear();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> acceptIncoming() async {
    final inc = incoming;
    if (inc == null || myUserId == null) return;

    // Coupe la sonnerie entrante dès qu'on accepte.
    await RingtoneService.instance.stop();

    final result = await _calls.accept(inc.callId);
    isGroupCall = result.isGroup || inc.isGroup;
    isCallInitiator = false;
    activeCallId = inc.callId;   // activeCallId défini AVANT incoming = null
    activeConvId = inc.convId;
    activePeerName = inc.displayTitle;
    activeType = inc.callType;
    activeRole = ActiveCallRole.ongoing;
    incoming = null;             // incoming mis à null APRÈS

    _rt.callState(
      inc.callId,
      "joined",
      userId: myUserId,
      displayName: myDisplayName,
    );

    for (final p in result.activeParticipants) {
      participantNames[p.userId] = p.displayName;
      joinedParticipantIds.add(p.userId);
    }
    joinedParticipantIds.add(myUserId!);
    notifyListeners();

    await _ensureMesh();
    for (final p in result.activeParticipants) {
      if (p.userId != myUserId) {
        await _mesh?.connectToPeer(p.userId);
      }
    }
    notifyListeners();
  }

  Future<void> rejectIncoming() async {
    final inc = incoming;
    if (inc == null) return;
    // Coupe la sonnerie entrante dès qu'on rejette.
    await RingtoneService.instance.stop();
    await _calls.reject(inc.callId);
    _rt.callState(
      inc.callId,
      inc.isGroup ? "declined" : "rejected",
      userId: myUserId,
      displayName: myDisplayName,
    );
    _signalBuffer.remove(inc.callId);
    incoming = null;
    notifyListeners();
  }

  Future<void> hangUp() async {
    final id = activeCallId ?? incoming?.callId;
    // Coupe TOUTE sonnerie (sortante ou entrante) : on raccroche.
    await RingtoneService.instance.stop();
    // Neutralise immédiatement pour bloquer les échos entrants pendant le nettoyage
    final wasGroup = isGroupCall;
    final wasInitiator = isCallInitiator;
    final wasRole = activeRole;
    activeCallId = null; // bloque _onEvent de traiter des états pendant le nettoyage
    try {
      if (id != null) {
        if (wasGroup && !wasInitiator && wasRole == ActiveCallRole.ongoing) {
          await _calls.leave(id);
          _rt.callState(id, "left", userId: myUserId, displayName: myDisplayName);
        } else {
          await _calls.end(id);
          _rt.callState(id, "ended", userId: myUserId, displayName: myDisplayName);
        }
      }
    } catch (_) {
    } finally {
      await _stopMesh();
      _clear();
    }
  }

  void _clear() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
    // Filet de sécurité : coupe toute sonnerie encore en cours.
    // (Doublon sûr des stop() éparpillés — mieux vaut couper 2 fois que 0.)
    RingtoneService.instance.stop();
    incoming = null;
    activeCallId = null;
    activeConvId = null;
    activePeerName = null;
    activeRole = null;
    isGroupCall = false;
    isCallInitiator = false;
    participantNames.clear();
    joinedParticipantIds.clear();
    notifyListeners();
  }

  Future<void> _ensureMesh() async {
    if (myUserId == null || activeCallId == null) return;

    final isVideo = activeType == "VIDEO";
    final perms = await ensureCallPermissions(video: isVideo);
    if (!perms) {
      lastError = isVideo
          ? "Micro et caméra requis pour l'appel"
          : "Micro requis pour l'appel";
      notifyListeners();
      throw Exception("PERMISSION_DENIED"); // ← FIX: throw au lieu de return silencieux
    }
    lastError = null;

    // Si le mesh existe déjà et le stream local est prêt, ne rien faire.
    if (_mesh != null && _mesh!.localStream != null) return;

    // FIX: utilise directement les serveurs ICE codés en dur dans l'application.
    // Plus d'appel réseau vers le backend pour récupérer /api/calls/ice.
    final ice = WebrtcPeerSession.fallbackIce;

    // Réinitialise si la mesh précédente était en erreur
    if (_mesh == null) {
      final callId = activeCallId!;
      _mesh = WebrtcGroupMesh(
        myUserId: myUserId!,
        isVideo: isVideo,
        iceServers: ice,
        onSendSignal: (peerId, sig) => _rt.callSignal(callId, peerId, sig),
        onUpdated: notifyListeners,
      );
    }

    try {
      await _mesh!.ensureLocal();
      notifyListeners();
    } catch (e) {
      lastError = "Connexion WebRTC impossible : micro/caméra inaccessible";
      debugPrint("[webrtc] mesh ensureLocal: $e");
      // Nettoie la mesh cassée pour permettre une nouvelle tentative
      await _mesh?.close();
      _mesh = null;
      notifyListeners();
    }
  }

  Future<void> _onPeerJoined(String userId, String? displayName) async {
    if (userId == myUserId || userId.isEmpty) return;
    if (displayName != null && displayName.isNotEmpty) {
      participantNames[userId] = displayName;
    }
    joinedParticipantIds.add(userId);
    if (activeRole == ActiveCallRole.outgoing) {
      activeRole = ActiveCallRole.ongoing;
      // Le destinataire a décroché : arrête la sonnerie sortante.
      await RingtoneService.instance.stop();
    }
    notifyListeners();
    await _ensureMesh();
    await _mesh?.connectToPeer(userId);
    notifyListeners();
  }

  Future<void> _onPeerLeft(String userId) async {
    joinedParticipantIds.remove(userId);
    await _mesh?.removePeer(userId);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    _iceServers ??= await _calls.iceServers();
    return _iceServers!;
  }

  Future<void> _stopMesh() async {
    await _mesh?.close();
    _mesh = null;
    _iceServers = null; // FIX: clear le cache ICE pour le prochain appel
  }

  void _bufferSignal(String callId, String from, Map<String, dynamic> signal) {
    _signalBuffer.putIfAbsent(callId, () => {})[from] ??= [];
    _signalBuffer[callId]![from]!.add(signal);
  }

  Future<void> _onEvent(Map<String, dynamic> e) async {
    final type = e["type"];
    debugPrint("[CallController] Événement reçu: $type");
    if (type == "incoming_call") {
      final callId = e["callId"] as String;
      DebugOverlay.log("CC 📞 APPEL: ${e["callerName"]}");
      debugPrint("[CallController] 📞 APPEL ENTRANT de ${e["callerName"]} !");
      incoming = IncomingCallInfo(
        callId: callId,
        convId: e["convId"] as String?,
        callType: e["callType"] as String? ?? "AUDIO",
        callerId: e["callerId"] as String,
        callerName: e["callerName"] as String? ?? "Appel",
        isGroup: (e["isGroup"] as bool?) ?? false,
        groupName: e["groupName"] as String?,
        memberCount: (e["memberCount"] as num?)?.toInt() ?? 2,
      );
      // Sonnerie entrante (loop) jusqu'à accept/reject/timeout serveur.
      RingtoneService.instance.startIncoming();
      notifyListeners();
    } else if (type == "call_signal") {
      final callId = e["callId"] as String?;
      final from = e["from"] as String?;
      final signal = e["signal"];
      if (callId == null || from == null || signal is! Map<String, dynamic>) return;
      if (callId != activeCallId) {
        _bufferSignal(callId, from, signal);
        return;
      }
      if (_mesh != null) {
        _mesh!.handleSignal(from, signal);
      } else {
        _bufferSignal(callId, from, signal);
      }
    } else if (type == "call_state") {
      final state = e["state"] as String?;
      final callId = e["callId"] as String?;
      final fromUserId = e["from"] as String?;
      final userId = e["userId"] as String? ?? fromUserId;
      final displayName = e["displayName"] as String?;

      if (callId == null) return;

      if (state == "joined" || state == "accepted") {
        // Ignore l'écho de notre propre "joined" (le serveur nous le renvoie maintenant)
        if (userId == myUserId) return;
        if (callId == activeCallId || callId == incoming?.callId) {
          _onPeerJoined(userId ?? "", displayName);
          // Flushe les signaux bufferisés pour ce callId
          final bufferedForCall = _signalBuffer.remove(callId);
          if (bufferedForCall != null && _mesh != null) {
            for (final peerEntry in bufferedForCall.entries) {
              for (final sig in peerEntry.value) {
                _mesh!.handleSignal(peerEntry.key, sig);
              }
            }
          }
        }
      } else if (state == "left" || state == "declined") {
        // Ignore notre propre départ (on le gère en local dans hangUp)
        if (userId == myUserId) return;
        if (callId == activeCallId && userId != null) {
          _onPeerLeft(userId);
        }
      } else if (state == "rejected" || state == "ended") {
        // "ended" émis par nous-mêmes via hangUp — on ignore l'écho
        if (fromUserId == myUserId) return;
        final isOurCall = callId == activeCallId ||
            callId == incoming?.callId ||
            (activeCallId == null && activeRole != null);
        if (isOurCall) {
          await _stopMesh();
          _signalBuffer.remove(callId);
          _clear();
        }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopMesh();
    super.dispose();
  }
}
