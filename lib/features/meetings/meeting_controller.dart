import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_permissions.dart';
import '../../core/realtime_client.dart';
import '../calls/webrtc_group_mesh.dart';
import '../calls/webrtc_peer_session.dart';
import 'meetings_repository.dart';

/// Contrôleur de réunion — gère l'état d'une réunion active (Google Meet style).
///
/// Réutilise WebrtcGroupMesh pour les connexions WebRTC peer-to-peer.
class MeetingController extends ChangeNotifier {
  MeetingController(this._repo, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final MeetingsRepository _repo;
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

    // Initialise WebRTC
    _iceServers = WebrtcPeerSession.fallbackIce;
    _mesh = WebrtcGroupMesh(
      myUserId: myUserId!,
      isVideo: isVideo,
      iceServers: _iceServers!,
      onSendSignal: (peerId, sig) {
        _rt.meetingSignal(meetingId, peerId, sig);
      },
      onUpdated: notifyListeners,
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
        _mesh?.connectToPeer(peerId);
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
    _mesh?.connectToPeer(userId);
    notifyListeners();
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
