import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_foreground_service.dart';
import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/realtime_client.dart';
import '../../core/ringtone_service.dart';
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
  // Fait « avancer » le minuteur affiché dans la salle/le bandeau. Sans tick,
  // l'interface ne se redessinait que sur les autres événements (muet, arrivée
  // d'un pair) et le chronomètre restait figé plusieurs minutes.
  Timer? _ticker;

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

  /// Durée prévue de la réunion, en secondes (0 = pas de limite). Posée au
  /// démarrage à partir du modèle [Meeting] pour alimenter le minuteur.
  int plannedDurationSec = 0;

  /// Organisateur de la réunion en cours. Lui seul peut prolonger.
  String? organiserId;

  bool get jeSuisOrganisateur => organiserId != null && organiserId == myUserId;

  /// Seuil de l'alerte « la fin approche », en secondes avant le terme.
  static const seuilFinProcheSec = 120;

  /// Supplément accordé par un clic sur « Prolonger ».
  static const prolongationSec = 15 * 60;

  /// Alertes de fin de réunion, émises UNE SEULE FOIS chacune.
  ///
  /// Un flux et non un simple booléen : ce sont des événements ponctuels — une
  /// tonalité, un bandeau — et non un état à afficher. Les exposer comme état
  /// obligerait l'écran à retenir lui-même ce qu'il a déjà joué, alors qu'il se
  /// reconstruit à chaque seconde sous l'effet du ticker.
  Stream<MeetingAlerte> get alertes => _alertes.stream;
  final StreamController<MeetingAlerte> _alertes =
      StreamController<MeetingAlerte>.broadcast();
  bool _finProcheEmise = false;
  bool _depassementEmis = false;

  /// Secondes écoulées depuis mon entrée dans la salle, ou nul si je n'y suis
  /// pas encore.
  int? get secondesEcoulees {
    final depuis = connectedSince;
    if (depuis == null) return null;
    return DateTime.now().difference(depuis).inSeconds;
  }

  /// Secondes restantes sur la durée prévue — négatif en dépassement, nul quand
  /// aucune durée n'a été fixée.
  int? get secondesRestantes {
    if (plannedDurationSec <= 0) return null;
    final ecoule = secondesEcoulees;
    if (ecoule == null) return null;
    return plannedDurationSec - ecoule;
  }

  // Participants
  final Map<String, String> _participantNames = {}; // userId -> displayName
  final Map<String, String?> _participantAvatars = {}; // userId -> avatarUrl
  final Set<String> _connectedPeerIds =
      {}; // participants annoncés par le serveur

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

  /// Mains levées des pairs, annoncées via la signalisation applicative.
  final Set<String> _raisedHands = {};

  /// Mon propre état de main levée.
  bool myHandRaised = false;

  /// Messages de chat reçus pendant la réunion (éphémères, non persistés).
  final List<MeetingChatMessage> _chatMessages = [];

  List<MeetingChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  /// Nombre de messages de chat non lus (tant que le panneau n'est pas ouvert).
  int _unreadChatCount = 0;
  int get unreadChatCount => _unreadChatCount;

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

  /// Le pair [peerId] a-t-il la main levée ?
  bool isHandRaised(String peerId) => _raisedHands.contains(peerId);

  /// Y a-t-il au moins une main levée (la mienne comprise) ?
  bool get hasRaisedHands => myHandRaised || _raisedHands.isNotEmpty;

  /// Rejoint la salle après une reconnexion WebSocket. La socket a changé, il
  /// faut se réinscrire côté serveur. Les paires WebRTC peuvent avoir survécu
  /// (coupure courte) : on ne les ferme pas ici. Au retour, `meeting_joined`
  /// nous donnera la liste à jour ; pour les pairs déjà connus, `connectToPeer`
  /// n'en recréera pas, et les pairs perdus seront retirés via `onPeerLost`.
  void _rejoinAfterReconnect() {
    final id = activeMeetingId;
    if (id == null || !isActive) return;
    debugPrint('[MeetingController] reconnexion WS → réinscription salle $id');
    _rt.meetingJoin(id);
    // Rediffuse mon état courant aux pairs (muet/caméra/main levée).
    _broadcastState();
  }

  void bindUser(String userId, String displayName) {
    myUserId = userId;
    myDisplayName = displayName;
  }

  /// Renseigne la durée prévue (en secondes), depuis le détail de la réunion.
  void setPlannedDuration(int seconds) {
    if (plannedDurationSec == seconds) return;
    plannedDurationSec = seconds;
    _armeSeuils();
    notifyListeners();
  }

  /// (Ré)arme les deux alertes à partir de l'état COURANT.
  ///
  /// Un seuil déjà franchi au moment où on l'arme est considéré comme consommé :
  /// une durée prévue qui nous parvient en retard, alors qu'elle est déjà
  /// dépassée, ne doit pas déclencher une tonalité pour un terme franchi depuis
  /// longtemps. Les alertes marquent un FRANCHISSEMENT, pas un état.
  void _armeSeuils() {
    final restant = secondesRestantes;
    if (restant == null) {
      _finProcheEmise = false;
      _depassementEmis = false;
      return;
    }
    _finProcheEmise = restant <= seuilFinProcheSec;
    _depassementEmis = restant <= 0;
  }

  /// Appelée à chaque tick : n'émet que sur le franchissement d'un seuil.
  void _verifieSeuils() {
    final restant = secondesRestantes;
    if (restant == null) return;
    if (!_finProcheEmise && restant <= seuilFinProcheSec) {
      _finProcheEmise = true;
      if (!_alertes.isClosed) _alertes.add(MeetingAlerte.finProche);
    }
    if (!_depassementEmis && restant <= 0) {
      _depassementEmis = true;
      if (!_alertes.isClosed) _alertes.add(MeetingAlerte.depassement);
    }
  }

  /// Prolonge la réunion de [prolongationSec].
  ///
  /// La nouvelle durée part du TEMPS DÉJÀ ÉCOULÉ quand celui-ci dépasse la durée
  /// prévue, et non de cette durée : prolonger alors qu'on est à vingt minutes
  /// de dépassement doit rendre du temps, pas laisser le minuteur dans le rouge.
  /// Il reste donc toujours exactement [prolongationSec] après le clic.
  ///
  /// Rien n'est appliqué localement : on attend `meeting_extended`, qui passe
  /// par le serveur et arrive à tout le monde en même temps. Une application
  /// optimiste ferait diverger l'organisateur du reste de la salle si le serveur
  /// refusait.
  void prolonger() {
    final id = activeMeetingId;
    if (id == null || !jeSuisOrganisateur) return;
    final ecoule = secondesEcoulees ?? 0;
    final base = plannedDurationSec > ecoule ? plannedDurationSec : ecoule;
    _rt.meetingExtend(id, base + prolongationSec);
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
    int? plannedDurationSec,
    String? organiserId,
  }) async {
    if (myUserId == null) return;
    if (activeMeetingId == meetingId && isActive) return;
    if (isActive) {
      throw StateError("ALREADY_IN_MEETING");
    }

    activeMeetingId = meetingId;
    activeIsVideo = isVideo;
    activeObjet = objet;
    plannedDurationSec = plannedDurationSec ?? 0;
    this.organiserId = organiserId;
    // Les seuils s'arment ici, avant toute connexion : `connectedSince` est
    // encore nul, donc rien n'est considéré comme franchi, et le premier tick
    // qui suivra l'entrée dans la salle fera foi.
    _armeSeuils();
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

    /*
     * 🔴 LA ROUTE AUDIO EST POSÉE ICI, ET C'EST CE QUI MANQUAIT.
     *
     * `isSpeakerOn` vaut `true` par défaut — ce qui est juste pour une réunion,
     * on ne tient pas son téléphone à l'oreille pendant une conférence — mais
     * `Helper.setSpeakerphoneOn` n'était appelé QUE dans `toggleSpeaker`. La
     * route restait donc celle laissée par ce qui précédait, et l'appel
     * précédent la remet à l'écouteur en se terminant.
     *
     * Résultat : le bouton affichait « haut-parleur activé » pendant que le son
     * sortait de l'écouteur, et le premier appui le passait à `false` — il
     * fallait appuyer DEUX FOIS pour obtenir le haut-parleur qu'on croyait déjà
     * avoir. Le bouton mentait.
     *
     * Règle générale qui en découle : un état par défaut ne vaut rien tant
     * qu'il n'a pas été APPLIQUÉ au système ; l'afficher ne le rend pas vrai.
     */
    try {
      await Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (_) {}

    // Rejoint via WebSocket. C'est le handler serveur qui inscrit la socket
    // dans la salle et renvoie la liste des participants déjà présents.
    _rt.meetingJoin(meetingId);
    _startTicker();
    notifyListeners();
  }

  /// Démarre (ou redémarre) le ticker qui notifie chaque seconde pour faire
  /// avancer le minuteur.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Les seuils sont évalués ICI et non dans l'écran : la salle peut être
      // réduite, l'alerte de fin doit tout de même partir.
      _verifieSeuils();
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Quitter la réunion en cours : coupe le média, arrête le service de
  /// premier plan et prévient le serveur.
  Future<void> leave() async {
    final meetingId = activeMeetingId;
    if (meetingId == null) return;

    _rt.meetingLeave(meetingId);
    await _stopMesh();
    CallForegroundService.arreter();
    _stopTicker();
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
      "cameraOff": isCameraOff,
      "handRaised": myHandRaised,
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

  /// Bascule la main levée et prévient les autres participants.
  void toggleHandRaised() {
    myHandRaised = !myHandRaised;
    _broadcastState();
    notifyListeners();
  }

  /// Envoie un message de chat à tous les participants. Le message est aussi
  /// ajouté localement (les autres le recevront par [meeting_signal]).
  void sendChatMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final id = activeMeetingId;
    if (id == null) return;

    final now = DateTime.now();
    final msg = MeetingChatMessage(
      fromUserId: myUserId ?? "",
      fromName: myDisplayName ?? "Moi",
      text: trimmed,
      sentAt: now,
      mine: true,
    );
    _chatMessages.add(msg);

    final payload = <String, dynamic>{
      "kind": "meeting_chat",
      "text": trimmed,
      "fromName": myDisplayName ?? "Participant",
      "ts": now.toUtc().toIso8601String(),
    };
    for (final peerId in _connectedPeerIds) {
      if (peerId != myUserId) {
        _rt.meetingSignal(id, peerId, payload);
      }
    }
    // La salle de chat est peut-être fermée : on incrémente le compteur de
    // non-lus. Réinitialisé quand on ouvre le panneau.
    if (!_chatOpen) _unreadChatCount++;
    notifyListeners();
  }

  bool _chatOpen = false;

  /// À appeler quand le panneau de chat est ouvert/fermé, pour gérer les
  /// messages non lus.
  void setChatOpen(bool open) {
    if (_chatOpen == open) return;
    _chatOpen = open;
    if (open && _unreadChatCount != 0) {
      _unreadChatCount = 0;
      notifyListeners();
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
      case "meeting_extended":
        // L'organisateur a repoussé le terme. La nouvelle durée vient du
        // serveur, pour tout le monde en même temps — l'organisateur compris,
        // qui n'a rien appliqué de son côté.
        final meetingId = e["meetingId"] as int?;
        final duree = (e["duree"] as num?)?.toInt();
        if (meetingId == activeMeetingId && duree != null) {
          plannedDurationSec = duree;
          // Réarmement : les deux alertes doivent pouvoir se déclencher de
          // nouveau à l'approche du NOUVEAU terme.
          _armeSeuils();
          notifyListeners();
        }
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
      case "ws_connected":
        // Reconnexion de la socket après une coupure. On se réinscrit dans la
        // salle, sinon la nouvelle socket n'est pas dans meetingRooms côté
        // serveur et plus aucun signal n'est relayé (média gelé). On n'émet
        // _mesh.ensureLocal() qu'au besoin (le flux local existe déjà).
        _rejoinAfterReconnect();
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
    // Ton d'arrivée (sauf pour nous-mêmes, filtré plus haut).
    RingtoneService.instance.playParticipantJoined();
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
    _raisedHands.remove(userId);
    _mesh?.removePeer(userId);
    RingtoneService.instance.playParticipantLeft();
    notifyListeners();
  }

  void _handleSignal(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    final signal = e["signal"] as Map<String, dynamic>?;
    if (fromUserId == null || signal == null) return;

    final kind = signal["kind"] as String?;

    // Signal applicatif : état d'un participant (muet/caméra/main levée).
    if (kind == "meeting_state") {
      var changed = false;
      final muted = signal["muted"] == true;
      if (_peerMuted[fromUserId] != muted) {
        _peerMuted[fromUserId] = muted;
        changed = true;
      }
      final hand = signal["handRaised"] == true;
      final hadHand = _raisedHands.contains(fromUserId);
      if (hand && !hadHand) {
        _raisedHands.add(fromUserId);
        changed = true;
      } else if (!hand && hadHand) {
        _raisedHands.remove(fromUserId);
        changed = true;
      }
      if (changed) notifyListeners();
      return;
    }

    // Signal applicatif : message de chat.
    if (kind == "meeting_chat") {
      final text = signal["text"] as String?;
      final fromName = signal["fromName"] as String? ??
          _participantNames[fromUserId] ??
          "Participant";
      final tsRaw = signal["ts"] as String?;
      final ts = tsRaw != null
          ? DateTime.tryParse(tsRaw) ?? DateTime.now()
          : DateTime.now();
      if (text != null && text.trim().isNotEmpty) {
        _chatMessages.add(MeetingChatMessage(
          fromUserId: fromUserId,
          fromName: fromName,
          text: text,
          sentAt: ts.toLocal(),
          mine: false,
        ));
        if (!_chatOpen) _unreadChatCount++;
        notifyListeners();
      }
      return;
    }

    // Sinon : signal de négociation WebRTC.
    _mesh?.handleSignal(fromUserId, signal);
  }

  void _clear() {
    _stopTicker();
    isActive = false;
    activeMeetingId = null;
    activeRoom = null;
    activeObjet = null;
    isMuted = false;
    isCameraOff = false;
    connectedSince = null;
    plannedDurationSec = 0;
    organiserId = null;
    _finProcheEmise = false;
    _depassementEmis = false;
    _roomScreensOpen = 0;
    _participantNames.clear();
    _participantAvatars.clear();
    _connectedPeerIds.clear();
    _peerMuted.clear();
    _raisedHands.clear();
    _chatMessages.clear();
    myHandRaised = false;
    _chatOpen = false;
    _unreadChatCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _alertes.close();
    _stopMesh();
    super.dispose();
  }
}

/// Franchissement d'un seuil de la durée prévue d'une réunion.
enum MeetingAlerte {
  /// Il reste [MeetingController.seuilFinProcheSec] ou moins.
  finProche,

  /// La durée prévue vient d'être atteinte ; on est en dépassement.
  depassement,
}

/// Message de chat échangé pendant une réunion. Éphémère, non persisté.
class MeetingChatMessage {
  MeetingChatMessage({
    required this.fromUserId,
    required this.fromName,
    required this.text,
    required this.sentAt,
    required this.mine,
  });

  final String fromUserId;
  final String fromName;
  final String text;
  final DateTime sentAt;
  final bool mine;
}
