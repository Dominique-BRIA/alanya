import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/realtime_client.dart';
import '../calls/calls_repository.dart';
import '../calls/webrtc_group_mesh.dart';
import '../calls/webrtc_peer_session.dart';
import 'meetings_repository.dart';

/// Contrôleur de réunion — gère l'état d'une réunion active (Google Meet style).
///
/// Réutilise WebrtcGroupMesh pour les connexions WebRTC peer-to-peer.
class MeetingController extends ChangeNotifier {
  MeetingController(this._repo, this._calls, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final MeetingsRepository _repo;
  final CallsRepository _calls;
  final RealtimeClient _rt;
  StreamSubscription? _sub;

  // État de la réunion
  int? activeMeetingId;
  String? activeRoom;
  bool isActive = false;
  bool isMuted = false;
  bool isCameraOff = false;
  bool isSpeakerOn = true;

  // Participants
  final Map<String, String> _participantNames = {}; // userId -> displayName
  final Set<String> _connectedPeerIds = {};

  // WebRTC
  WebrtcGroupMesh? _mesh;
  List<Map<String, dynamic>>? _iceServers;
  String? myUserId;
  String? myDisplayName;

  // Getters
  MediaStream? get localStream => _mesh?.localStream;
  Map<String, MediaStream> get remoteStreams => _mesh?.remoteStreams ?? {};
  int get connectedPeerCount => _mesh?.connectedCount ?? 0;
  Map<String, String> get participantNames => _participantNames;

  void bindUser(String userId, String displayName) {
    myUserId = userId;
    myDisplayName = displayName;
  }

  /// Rejoindre une réunion.
  Future<void> join(int meetingId, {required bool isVideo}) async {
    if (myUserId == null) return;

    activeMeetingId = meetingId;
    isActive = true;
    notifyListeners();

    // Demande les permissions
    final perms = await ensureCallPermissions(video: isVideo);
    if (!perms) {
      isActive = false;
      activeMeetingId = null;
      notifyListeners();
      throw Exception("PERMISSION_DENIED");
    }

    // Initialise WebRTC.
    //
    // On tente de récupérer les serveurs ICE/TURN du backend (HMAC temporaire),
    // comme le font les appels : sans TURN, une réunion derrière un NAT
    // symétrique (réseaux mobiles restrictifs) n'aboutit pas. Le STUN codé en
    // dur reste le repli si l'endpoint est indisponible.
    try {
      _iceServers = await _loadIceServers();
    } catch (e) {
      debugPrint('[MeetingController] ICE backend indisponible, fallback STUN: $e');
      _iceServers = WebrtcPeerSession.fallbackIce;
    }
    _mesh = WebrtcGroupMesh(
      myUserId: myUserId!,
      isVideo: isVideo,
      iceServers: _iceServers!,
      onSendSignal: (peerId, sig) {
        _rt.meetingSignal(meetingId, peerId, sig);
      },
      onUpdated: notifyListeners,
      // Un participant dont la connexion média est définitivement perdue est
      // retiré de la grille : sans ce câblage il y restait figé jusqu'à la fin.
      onPeerLost: _onPeerLost,
    );
    await _mesh!.ensureLocal();

    // Rejoint via WebSocket
    _rt.meetingJoin(meetingId);
    notifyListeners();
  }

  /// Quitter la réunion.
  Future<void> leave() async {
    final meetingId = activeMeetingId;
    if (meetingId == null) return;

    _rt.meetingLeave(meetingId);
    await _stopMesh();
    _clear();
  }

  /// Toggle micro.
  void toggleMute() {
    isMuted = !isMuted;
    _mesh?.localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
    notifyListeners();
  }

  /// Toggle caméra.
  void toggleCamera() {
    isCameraOff = !isCameraOff;
    _mesh?.localStream?.getVideoTracks().forEach((track) {
      track.enabled = !isCameraOff;
    });
    notifyListeners();
  }

  /// Toggle haut-parleur.
  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    Helper.setSpeakerphoneOn(isSpeakerOn);
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> e) {
    final type = e["type"] as String?;
    if (type == null) return;

    switch (type) {
      case "meeting_joined":
        _handleJoined(e);
        break;
      case "meeting_user_joined":
        _handleUserJoined(e);
        break;
      case "meeting_user_left":
        _handleUserLeft(e);
        break;
      case "meeting_signal":
        _handleSignal(e);
        break;
    }
  }

  void _handleJoined(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final participants = (e["participants"] as List?)?.cast<String>() ?? [];
    // Connecte WebRTC aux participants déjà présents
    for (final peerId in participants) {
      if (peerId != myUserId) {
        // J'entre dans la salle : les présents sont là avant moi, ils offrent.
        _mesh?.connectToPeer(peerId, asOfferer: false);
        _connectedPeerIds.add(peerId);
      }
    }
    notifyListeners();
  }

  void _handleUserJoined(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final userId = e["userId"] as String?;
    final displayName = e["displayName"] as String? ?? "Participant";
    if (userId == null || userId == myUserId) return;

    _participantNames[userId] = displayName;
    _connectedPeerIds.add(userId);
    // Il entre après moi : j'offre. Les deux rôles étant portés par deux
    // événements distincts, deux pairs ne peuvent jamais s'offrir mutuellement.
    _mesh?.connectToPeer(userId, asOfferer: true);
    notifyListeners();
  }

  /// Connexion média perdue avec un pair (coupure réseau, crash de l'app, etc.).
  ///
  /// Le retrait de la maille précède la confirmation éventuelle du serveur, qui
  /// peut ne jamais arriver (socket tombée sans `meeting_leave`) : la grille
  /// resterait figée sur un flux mort. L'état de participation côté base sera
  /// corrigé par le prochain `meeting_user_left` ou à la prochaine synchronisation.
  void _onPeerLost(String peerId) {
    if (activeMeetingId == null) return;
    traceAppel('réunion : pair $peerId perdu, retrait de la grille');
    _participantNames.remove(peerId);
    _connectedPeerIds.remove(peerId);
    _mesh?.removePeer(peerId);
    notifyListeners();
  }

  /// Récupère les serveurs ICE/TURN depuis le backend, avec cache le temps de
  /// la réunion (les identifiants TURN sont des HMAC temporaires).
  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    if (_iceServers != null) return _iceServers!;
    _iceServers = await _calls.iceServers();
    return _iceServers!;
  }

  void _handleUserLeft(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final userId = e["userId"] as String?;
    if (userId == null) return;

    _participantNames.remove(userId);
    _connectedPeerIds.remove(userId);
    _mesh?.removePeer(userId);
    notifyListeners();
  }

  void _handleSignal(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    final signal = e["signal"] as Map<String, dynamic>?;
    if (fromUserId == null || signal == null) return;

    _mesh?.handleSignal(fromUserId, signal);
  }

  Future<void> _stopMesh() async {
    await _mesh?.close();
    _mesh = null;
  }

  void _clear() {
    isActive = false;
    activeMeetingId = null;
    activeRoom = null;
    isMuted = false;
    isCameraOff = false;
    _participantNames.clear();
    _connectedPeerIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopMesh();
    super.dispose();
  }
}
