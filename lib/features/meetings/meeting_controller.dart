import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_foreground_service.dart';
import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/realtime_client.dart';
import '../calls/calls_repository.dart';
import '../calls/webrtc_group_mesh.dart';
import '../calls/webrtc_peer_session.dart';

/// Contrôleur GLOBAL de réunion, à l'image de [CallController] pour les appels.
///
/// Global plutôt qu'instancié par écran, car la réunion doit survivre à la
/// fermeture de la salle : l'utilisateur doit pouvoir la réduire, naviguer
/// dans l'app (lire ses messages) et revenir par le bandeau, sans couper
/// l'audio. Le service de premier plan Android garde le processus vivant.
class MeetingController extends ChangeNotifier {
  MeetingController(this._calls, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final CallsRepository _calls;
  final RealtimeClient _rt;
  StreamSubscription? _sub;

  // ── État de la réunion active ────────────────────────────────────────────
  int? activeMeetingId;
  String? activeRoom;
  String? activeObjet;
  bool activeIsVideo = false;
  bool isActive = false;
  bool isMuted = false;
  bool isCameraOff = false;
  bool isSpeakerOn = true;

  /// Début effectif de la participation (réception du `meeting_joined`). Source
  /// unique du minuteur, affiché à la fois dans la salle et dans le bandeau.
  DateTime? connectedSince;

  // Participants
  final Map<String, String> _participantNames = {}; // userId -> displayName
  final Set<String> _connectedPeerIds = {};

  // WebRTC
  WebrtcGroupMesh? _mesh;
  List<Map<String, dynamic>>? _iceServers;
  String? myUserId;
  String? myDisplayName;

  // Compteur d'écrans de salle ouverts (0 = la salle n'est pas affichée, donc le
  // bandeau global doit l'être). Voir CallController.setCallScreenVisible pour
  // le pourquoi d'un compteur plutôt qu'un booléen.
  int _roomScreensOpen = 0;
  bool get roomVisible => _roomScreensOpen > 0;

  // Getters
  MediaStream? get localStream => _mesh?.localStream;
  Map<String, MediaStream> get remoteStreams => _mesh?.remoteStreams ?? {};
  int get connectedPeerCount => _mesh?.connectedCount ?? 0;
  Map<String, String> get participantNames => _participantNames;

  void bindUser(String userId, String displayName) {
    myUserId = userId;
    myDisplayName = displayName;
  }

  void setRoomVisible(bool v) {
    final avant = roomVisible;
    if (v) {
      _roomScreensOpen++;
    } else if (_roomScreensOpen > 0) {
      _roomScreensOpen--;
    }
    if (roomVisible == avant) return;
    notifyListeners();
  }

  /// Rejoindre une réunion.
  ///
  /// Idempotent : si on est déjà dans [meetingId], ne refait rien. Si on est
  /// dans une AUTRE réunion, refuse : il faut d'abord quitter.
  Future<void> join(
    int meetingId, {
    required bool isVideo,
    String? objet,
  }) async {
    if (myUserId == null) return;
    if (activeMeetingId == meetingId && isActive) return;
    if (isActive) {
      throw StateError("ALREADY_IN_MEETING");
    }

    activeMeetingId = meetingId;
    activeIsVideo = isVideo;
    activeObjet = objet;
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

    // Serveurs ICE/TURN du backend (HMAC), avec repli STUN — même chose que
    // pour les appels, sinon les NAT symétriques coupent les réunions.
    try {
      _iceServers = await _loadIceServers();
    } catch (e) {
      debugPrint(
          '[MeetingController] ICE backend indisponible, fallback STUN: $e');
      _iceServers = WebrtcPeerSession.fallbackIce;
    }
    _mesh = WebrtcGroupMesh(
      myUserId: myUserId!,
      isVideo: isVideo,
      iceServers: _iceServers!,
      onSendSignal: (peerId, sig) {
        _rt.meetingSignal(meetingId, peerId, sig);
      },
      onUpdated: _onMeshUpdated,
      onPeerLost: _onPeerLost,
    );
    await _mesh!.ensureLocal();

    // Rejoint via WebSocket. C'est le handler serveur qui inscrit la socket
    // dans la salle et renvoie la liste des participants déjà présents.
    _rt.meetingJoin(meetingId);
    notifyListeners();
  }

  /// Quitter la réunion en cours : coupe le média, arrête le service de
  /// premier plan et prévient le serveur.
  Future<void> leave() async {
    final meetingId = activeMeetingId;
    if (meetingId == null) return;

    _rt.meetingLeave(meetingId);
    await _stopMesh();
    CallForegroundService.arreter();
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

  /// Bascule caméra avant/arrière.
  Future<void> switchCamera() async {
    await _mesh?.switchCamera();
  }

  /// Toggle haut-parleur.
  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    await Helper.setSpeakerphoneOn(isSpeakerOn);
    notifyListeners();
  }

  // ── WebRTC ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    if (_iceServers != null) return _iceServers!;
    _iceServers = await _calls.iceServers();
    return _iceServers!;
  }

  /// Appelé par le mesh à chaque changement (piste ajoutée, mute, etc.). On en
  /// profite pour :
  ///  - poser `connectedSince` au premier signe d'activité (flux local prêt),
  ///    ce qui lance le minuteur ;
  ///  - démarrer le service de premier plan afin que l'audio survive à l'écran
  ///    éteint ou au passage en arrière-plan.
  void _onMeshUpdated() {
    if (isActive && connectedSince == null && _mesh?.localStream != null) {
      connectedSince = DateTime.now();
      // Démarré ICI et non dans join : tant que le flux local n'est pas prêt,
      // il n'y a rien à protéger. Ne fait rien hors Android.
      CallForegroundService.demarrer(
        titre: activeObjet ?? "Réunion en cours",
      );
    }
    notifyListeners();
  }

  /// Connexion média perdue avec un pair (crash, coupure réseau). On le
  /// retire sans attendre un hypothétique `meeting_user_left`.
  void _onPeerLost(String peerId) {
    if (activeMeetingId == null) return;
    traceAppel('réunion : pair $peerId perdu, retrait de la grille');
    _participantNames.remove(peerId);
    _connectedPeerIds.remove(peerId);
    _mesh?.removePeer(peerId);
    notifyListeners();
  }

  Future<void> _stopMesh() async {
    await _mesh?.close();
    _mesh = null;
    _iceServers = null;
  }

  // ── Événements temps réel ────────────────────────────────────────────────

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
      case "meeting_ended":
        // L'organisateur a terminé la réunion : tout le monde est déconnecté.
        final meetingId = e["meetingId"];
        if (meetingId == activeMeetingId) {
          _stopMesh();
          CallForegroundService.arreter();
          _clear();
        }
        break;
    }
  }

  void _handleJoined(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final participants = (e["participants"] as List?)?.cast<String>() ?? [];
    // Connecte WebRTC aux participants déjà présents : j'entre dans la salle,
    // les présents sont là avant moi, ils offrent.
    for (final peerId in participants) {
      if (peerId != myUserId) {
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
    // Il entre après moi : j'offre. Deux événements distincts portent les deux
    // rôles, donc deux pairs ne peuvent jamais s'offrir mutuellement.
    _mesh?.connectToPeer(userId, asOfferer: true);
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

  void _clear() {
    isActive = false;
    activeMeetingId = null;
    activeRoom = null;
    activeObjet = null;
    isMuted = false;
    isCameraOff = false;
    connectedSince = null;
    _roomScreensOpen = 0;
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
