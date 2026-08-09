import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_foreground_service.dart';
import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/realtime_client.dart';
import '../../models/meeting.dart';
import '../calls/calls_repository.dart';
import '../calls/webrtc_group_mesh.dart';
import '../calls/webrtc_peer_session.dart';
import 'meetings_repository.dart';

/// Contrôleur GLOBAL de réunion, à l'image de [CallController] pour les appels.
///
/// Global plutôt qu'instancié par écran, car la réunion doit survivre à la
/// fermeture de la salle : l'utilisateur doit pouvoir la réduire, naviguer
/// dans l'app (lire ses messages) et revenir par le bandeau, sans couper
/// l'audio. Le service de premier plan Android garde le processus vivant.
class MeetingController extends ChangeNotifier {
  MeetingController(this._calls, this._meetings, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final CallsRepository _calls;
  final MeetingsRepository _meetings;
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
  final Map<String, String?> _participantAvatars = {}; // userId -> avatarUrl
  final Set<String> _connectedPeerIds = {}; // participants annoncés par le serveur

  /// État muet des pairs, tel qu'annoncé par eux-mêmes via la signalisation
  /// applicative (`meeting_signal` de type `state`).
  ///
  /// On ne peut pas se fier à `MediaStreamTrack.muted`/`onMute` : ces valeurs
  /// ne changent que pour des causes externes (coupure réseau), pas quand
  /// l'autre utilisateur coupe son micro avec `track.enabled = false` — et
  /// c'est précisément ce qu'on veut afficher. On fait donc circuler l'état
  /// muet dans le canal de signalisation déjà relayé de pair à pair par le
  /// serveur, qui n'en inspecte pas le contenu.
  final Map<String, bool> _peerMuted = {};

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
  Map<String, String?> get participantAvatars => _participantAvatars;

  /// Identifiants des participants actuellement dans la salle (moi exclu).
  ///
  /// Source de vérité pour l'affichage, indépendante de la négociation WebRTC :
  /// l'événement `meeting_joined` ne donne que ces IDs, sans les noms. On
  /// résout ces noms via le détail de la réunion ; en attendant, les
  /// interfaces doivent s'appuyer sur cette liste plutôt que sur les clés de
  /// [participantNames], sinon les participants déjà présents à notre arrivée
  /// restent invisibles.
  List<String> get peerIds => _connectedPeerIds.toList();

  /// Nombre de participants logiquement présents dans la salle (moi compris),
  /// indépendamment de l'état de négociation WebRTC. Plus fiable que
  /// [connectedPeerCount] + 1, qui ne compte que les pairs dont le flux média
  /// est déjà établi (un nouveau venu y manquait pendant quelques secondes).
  int get participantCount => _connectedPeerIds.length + 1;

  /// Le pair [peerId] a-t-il son micro coupé ? Faux si on ne sait pas encore.
  bool isPeerMuted(String peerId) => _peerMuted[peerId] ?? false;

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
    _broadcastState();
    notifyListeners();
  }

  /// Diffuse mon état (muet ou non) à tous les pairs déjà connectés, via le
  /// canal de signalisation applicatif. Appelé après un toggle et à l'arrivée
  /// d'un nouveau pair pour qu'il connaisse mon état courant.
  void _broadcastState({String? onlyTo}) {
    final id = activeMeetingId;
    if (id == null) return;
    final payload = {
      "kind": "meeting_state",
      "muted": isMuted,
    };
    if (onlyTo != null) {
      _rt.meetingSignal(id, onlyTo, payload);
    } else {
      for (final peerId in _connectedPeerIds) {
        if (peerId != myUserId) {
          _rt.meetingSignal(id, peerId, payload);
        }
      }
    }
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

  /// Renseigne les noms/avatars des participants déjà présents à notre arrivée.
  ///
  /// L'événement `meeting_joined` ne contient que des IDs, sans les noms. On
  /// complète avec le détail de la réunion, qui liste tous les participants.
  /// Les participants annoncés par `meeting_user_joined` (avec leur nom) ne
  /// sont pas écrasés. Échec silencieux : on se contentera du repli
  /// « Participant » le temps du rafraîchissement suivant.
  Future<void> _hydrateParticipants(int meetingId) async {
    try {
      final meeting = await _meetings.fetchMeeting(meetingId);
      var changed = false;
      for (final p in meeting.participants) {
        if (p.userId == myUserId) continue;
        if (!_participantNames.containsKey(p.userId)) {
          _participantNames[p.userId] = p.displayName;
          changed = true;
        }
        if (p.avatarUrl != null &&
            _participantAvatars[p.userId] != p.avatarUrl) {
          _participantAvatars[p.userId] = p.avatarUrl;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('[MeetingController] hydratation participants échouée: $e');
    }
  }

  /// Renseigne l'avatar d'un participant (venu du détail de la réunion), pour
  /// l'afficher en l'absence de flux vidéo.
  void setParticipantAvatar(String userId, String? avatarUrl) {
    if (avatarUrl == null) {
      _participantAvatars.remove(userId);
    } else {
      _participantAvatars[userId] = avatarUrl;
    }
    notifyListeners();
  }

  /// Enregistre les avatars d'une liste de participants [ {userId, avatarUrl} ].
  void setParticipantAvatars(Iterable<MapEntry<String, String?>> entries) {
    var changed = false;
    for (final e in entries) {
      if (e.value == null) {
        changed |= _participantAvatars.remove(e.key) != null;
      } else if (_participantAvatars[e.key] != e.value) {
        _participantAvatars[e.key] = e.value;
        changed = true;
      }
    }
    if (changed) notifyListeners();
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
    _participantAvatars.remove(peerId);
    _connectedPeerIds.remove(peerId);
    _peerMuted.remove(peerId);
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
    if (meetingId == null || meetingId != activeMeetingId) return;

    final participants = (e["participants"] as List?)?.cast<String>() ?? [];
    // Connecte WebRTC aux participants déjà présents : j'entre dans la salle,
    // les présents sont là avant moi, ils offrent.
    for (final peerId in participants) {
      if (peerId != myUserId) {
        _mesh?.connectToPeer(peerId, asOfferer: false);
        _connectedPeerIds.add(peerId);
      }
    }
    // L'événement ne contient que les IDs : on résout noms et avatars depuis le
    // détail de la réunion, sinon les participants déjà présents restent
    // invisibles dans la grille et la fiche participants.
    _hydrateParticipants(meetingId);
    // Annonce mon état muet courant à ceux déjà présents.
    _broadcastState();
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
    // Lui communique mon état muet courant, sinon il m'afficherait toujours
    // « micro actif » tant que je ne bascule pas moi-même.
    _broadcastState(onlyTo: userId);
    notifyListeners();
  }

  void _handleUserLeft(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final userId = e["userId"] as String?;
    if (userId == null) return;

    _participantNames.remove(userId);
    _participantAvatars.remove(userId);
    _connectedPeerIds.remove(userId);
    _peerMuted.remove(userId);
    _mesh?.removePeer(userId);
    notifyListeners();
  }

  void _handleSignal(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    final signal = e["signal"] as Map<String, dynamic>?;
    if (fromUserId == null || signal == null) return;

    // Signal applicatif (état muet) : il transite dans le même canal que la
    // négociation WebRTC mais n'est pas pour elle.
    if (signal["kind"] == "meeting_state") {
      final muted = signal["muted"] == true;
      if (_peerMuted[fromUserId] != muted) {
        _peerMuted[fromUserId] = muted;
        notifyListeners();
      }
      return;
    }

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
    _participantAvatars.clear();
    _connectedPeerIds.clear();
    _peerMuted.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopMesh();
    super.dispose();
  }
}
