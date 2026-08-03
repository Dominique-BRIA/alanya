import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/call_ui_native.dart';
import '../../core/lock_screen_call.dart';
import '../../core/push_service.dart';
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
  String? activePeerAvatarUrl;
  final Map<String, String> participantAvatars = {};
  String activeType = "AUDIO";
  ActiveCallRole? activeRole;
  bool isGroupCall = false;
  bool isCallInitiator = false;
  final Map<String, String> participantNames = {};
  final Set<String> joinedParticipantIds = {};
  // Participants ayant rejoint un appel DÉJÀ en cours (invitation / transfert).
  // Sert à les marquer « (invité) » et à mettre en évidence le nouvel
  // interlocuteur, pour éviter la confusion après un transfert.
  final Set<String> invitedParticipantIds = {};
  // Membres connus au démarrage de l'appel (correspondant 1-1 ou membres du
  // groupe). Un « invité » = quelqu'un qui rejoint un appel en cours ET qui
  // n'était PAS un membre initial (évite de taguer un membre de groupe qui
  // décroche en retard).
  final Set<String> _initialMemberIds = {};

  WebrtcGroupMesh? _mesh;
  final Map<String, Map<String, List<Map<String, dynamic>>>> _signalBuffer = {};
  List<Map<String, dynamic>>? _iceServers;
  String? lastError;

  // --- Contrôles d'appel (Lot 1) ---
  bool get isMuted => _mesh != null && !_mesh!.micEnabled;
  bool get isVideoEnabled => _mesh?.cameraEnabled ?? (activeType == "VIDEO");
  bool isSpeakerOn = false;
  // Passe à true quand l'écran d'appel s'affiche chez le correspondant (Lot 2).
  bool remoteRinging = false;

  // Lot 2b — minimisation : l'écran plein-écran d'appel est-il affiché ?
  // Quand false pendant un appel actif, on montre le bandeau global.
  bool callScreenVisible = false;
  // Début de la connexion média (source unique pour le minuteur, écran + bandeau).
  DateTime? connectedSince;

  // Lot 4 — transfert supervisé : on a invité une cible et on attend qu'elle
  // rejoigne pour quitter automatiquement.
  bool _pendingTransfer = false;
  String? _transferTargetId;
  bool get isTransferring => _pendingTransfer;

  void setCallScreenVisible(bool v) {
    if (callScreenVisible == v) return;
    callScreenVisible = v;
    notifyListeners();
  }

  MediaStream? get localStream => _mesh?.localStream;
  Map<String, MediaStream> get remoteStreams => _mesh?.remoteStreams ?? {};
  int get connectedPeerCount => _mesh?.connectedCount ?? 0;
  bool get mediaConnected => connectedPeerCount > 0;

  /// FIX: activeRole est inclus pour éviter que isBusy == false
  /// pendant la transition incoming → activeCallId dans acceptIncoming().
  bool get isBusy =>
      activeCallId != null || incoming != null || activeRole != null;

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
    debugPrint(
        "[CallController] Appel créé sur le backend, envoi du signal call_ring...");
    _rt.callRing(started.id);
    activeCallId = started.id;
    activeConvId = convId;
    isGroupCall = started.isGroup;
    isCallInitiator = true;
    activePeerName = started.isGroup ? (started.groupName ?? title) : title;
    activePeerAvatarUrl = started.isGroup
        ? null
        : (started.callees.isNotEmpty ? started.callees.first.avatarUrl : null);
    activeType = type;
    activeRole = ActiveCallRole.outgoing;
    participantNames.clear();
    joinedParticipantIds.clear();
    invitedParticipantIds.clear();
    _initialMemberIds.clear();
    if (myUserId != null) {
      joinedParticipantIds.add(myUserId!);
      _initialMemberIds.add(myUserId!);
    }
    for (final c in started.callees) {
      participantNames[c.userId] = c.pseudo ?? c.publicNumber ?? "Membre";
      if (c.avatarUrl != null) participantAvatars[c.userId] = c.avatarUrl!;
      _initialMemberIds.add(c.userId); // membres appelés dès le départ
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
      _rt.callState(started.id, "ended",
          userId: myUserId, displayName: myDisplayName);
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
    PushService.instance.cancelIncomingCall(inc.callId); // retire la notif

    final result = await _calls.accept(inc.callId);
    isGroupCall = result.isGroup || inc.isGroup;
    isCallInitiator = false;
    activeCallId = inc.callId; // activeCallId défini AVANT incoming = null
    activeConvId = inc.convId;
    activePeerName = inc.displayTitle;
    activePeerAvatarUrl = inc.isGroup ? null : inc.callerAvatarUrl;
    if (inc.callerAvatarUrl != null) {
      participantAvatars[inc.callerId] = inc.callerAvatarUrl!;
    }
    // Sécurité : le nom de l'appelant doit survivre après la nullification de incoming
    // (écran ActiveCallScreen lisait incoming?.displayTitle ?? "Appel" et retombait sur "Appel")
    participantNames[inc.callerId] = inc.callerName;
    _initialMemberIds.clear();
    _initialMemberIds.add(myUserId!);
    _initialMemberIds.add(inc.callerId);
    joinedParticipantIds.add(inc.callerId);

    activeType = inc.callType;
    activeRole = ActiveCallRole.ongoing;
    incoming = null; // incoming mis à null APRÈS

    _rt.callState(
      inc.callId,
      "joined",
      userId: myUserId,
      displayName: myDisplayName,
    );

    for (final p in result.activeParticipants) {
      participantNames[p.userId] = p.displayName;
      joinedParticipantIds.add(p.userId);
      _initialMemberIds.add(p.userId); // membres déjà présents à l'acceptation
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

  /// Accepte un appel dont on ne connaît QUE l'identifiant.
  ///
  /// C'est le cas quand l'utilisateur décroche depuis l'écran natif ou la
  /// notification alors que l'application était fermée : décrocher la démarre,
  /// et à cet instant `incoming` est vide — la trame WebSocket n'est pas encore
  /// arrivée. [acceptIncoming] sortirait donc sans rien faire.
  ///
  /// Attendre cette trame était l'ancienne approche, et elle est fragile : si
  /// elle tarde ou ne vient pas, l'application s'ouvre sur l'accueil et l'appel
  /// semble perdu. Ici le serveur est appelé directement, avec le seul
  /// identifiant. Les informations d'affichage manquantes — nom, avatar —
  /// viennent de ce que le serveur renvoie, et la trame WebSocket, si elle
  /// arrive ensuite, ne fait que confirmer un état déjà établi.
  Future<bool> acceptById(String callId, {String? nomAffiche}) async {
    if (myUserId == null) return false;
    // Un appel déjà en cours signifie que la trame est arrivée entre-temps et
    // que le chemin normal a fait le travail : ne rien refaire.
    if (activeCallId == callId) return true;

    await RingtoneService.instance.stop();
    PushService.instance.cancelIncomingCall(callId);

    try {
      final result = await _calls.accept(callId);
      isGroupCall = result.isGroup;
      isCallInitiator = false;
      activeCallId = callId;
      activePeerName = result.groupName ?? nomAffiche ?? activePeerName ?? "Appel";
      activeRole = ActiveCallRole.ongoing;
      incoming = null;

      _initialMemberIds
        ..clear()
        ..add(myUserId!);
      joinedParticipantIds
        ..clear()
        ..add(myUserId!);
      for (final p in result.activeParticipants) {
        participantNames[p.userId] = p.displayName;
        joinedParticipantIds.add(p.userId);
        _initialMemberIds.add(p.userId);
        // Sans correspondant nommé, l'écran afficherait « Appel » : le premier
        // participant actif qui n'est pas moi est l'interlocuteur.
        if (p.userId != myUserId && nomAffiche == null && !result.isGroup) {
          activePeerName = p.displayName;
        }
      }

      _rt.callState(callId, "joined",
          userId: myUserId, displayName: myDisplayName);
      notifyListeners();

      await _ensureMesh();
      for (final p in result.activeParticipants) {
        if (p.userId != myUserId) await _mesh?.connectToPeer(p.userId);
      }
      notifyListeners();
      return true;
    } catch (e) {
      // 409 : l'appel n'est plus disponible — l'appelant a renoncé pendant que
      // l'application démarrait, ou le délai a expiré.
      lastError = "Cet appel n'est plus disponible";
      _clear();
      notifyListeners();
      return false;
    }
  }

  Future<void> rejectIncoming() async {
    final inc = incoming;
    if (inc == null) return;
    // Coupe la sonnerie entrante dès qu'on rejette.
    await RingtoneService.instance.stop();
    PushService.instance.cancelIncomingCall(inc.callId); // retire la notif
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
    activeCallId =
        null; // bloque _onEvent de traiter des états pendant le nettoyage
    try {
      if (id != null) {
        if (wasGroup && !wasInitiator && wasRole == ActiveCallRole.ongoing) {
          await _calls.leave(id);
          _rt.callState(id, "left",
              userId: myUserId, displayName: myDisplayName);
        } else {
          await _calls.end(id);
          _rt.callState(id, "ended",
              userId: myUserId, displayName: myDisplayName);
        }
      }
    } catch (_) {
    } finally {
      await _stopMesh();
      _clear();
    }
  }

  /// Un autre appareil connecté au **même compte** a pris la main sur cet appel
  /// (décroché ou refusé). Le serveur nous relaie son `call_state`, portant
  /// notre propre identifiant — d'où la confusion possible avec l'écho de nos
  /// propres actions.
  ///
  /// Deux garde-fous distinguent les deux cas : l'appel doit être en cours de
  /// sonnerie chez nous (`incoming`), et ne pas être celui que nous venons
  /// nous-mêmes d'accepter (`activeCallId`).
  ///
  /// On se contente de nettoyer localement : **rien n'est envoyé au serveur**,
  /// sans quoi on raccrocherait l'appel que l'autre appareil vient de prendre.
  bool _takenByAnotherDevice(String callId) {
    if (incoming == null || incoming!.callId != callId) return false;
    if (callId == activeCallId) return false; // c'est nous qui avons agi
    _clear(); // coupe la sonnerie, retire la notification, notifie l'UI
    return true;
  }

  void _clear() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
    // Filet de sécurité : coupe toute sonnerie encore en cours.
    // (Doublon sûr des stop() éparpillés — mieux vaut couper 2 fois que 0.)
    RingtoneService.instance.stop();
    final idAFermer = activeCallId ?? incoming?.callId;
    PushService.instance.cancelIncomingCall(idAFermer); // retire la notif
    // Referme aussi l'ÉCRAN D'APPEL NATIF. Sans cela il continuerait de sonner
    // par-dessus le verrouillage alors que l'appelant a déjà raccroché : le
    // paquet ne sait pas que l'appel est terminé, personne ne le lui a dit.
    if (idAFermer != null) CallUiNative.masquer(idAFermer);
    // Rend la main au verrouillage : sans ce retour, l'application resterait
    // accessible écran verrouillé bien après la fin de l'appel.
    LockScreenCall.desactiver();
    incoming = null;
    activeCallId = null;
    activeConvId = null;
    activePeerName = null;
    activePeerAvatarUrl = null;
    participantAvatars.clear();
    activeRole = null;
    isGroupCall = false;
    isCallInitiator = false;
    participantNames.clear();
    joinedParticipantIds.clear();
    invitedParticipantIds.clear();
    _initialMemberIds.clear();
    remoteRinging = false;
    isSpeakerOn = false;
    connectedSince = null;
    callScreenVisible = false;
    _pendingTransfer = false;
    _transferTargetId = null;
    notifyListeners();
  }

  // Démarre le minuteur dès que le média est réellement connecté.
  void _onMeshUpdated() {
    if (mediaConnected && connectedSince == null) {
      connectedSince = DateTime.now();
    }
    notifyListeners();
  }

  // --- Contrôles média (Lot 1) ---
  void toggleMute() {
    final m = _mesh;
    if (m == null) return;
    m.setMic(!m.micEnabled);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (_) {}
    notifyListeners();
  }

  void toggleVideo() {
    final m = _mesh;
    if (m == null) return;
    m.setCamera(!m.cameraEnabled);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _mesh?.switchCamera();
  }

  /// Émis par l'appelé quand son écran d'appel s'affiche : informe l'appelant
  /// que « ça sonne » réellement chez lui (état « En train de sonner »).
  void notifyRingingDisplayed() {
    final id = incoming?.callId;
    if (id != null) _rt.callState(id, "ringing", userId: myUserId);
  }

  // --- Lot 5 : inviter dans l'appel (appel de groupe dynamique) ---
  /// Invite `publicNumber` dans l'appel en cours SANS quitter (contrairement au
  /// transfert). L'appel devient multi-partie ; le mesh connectera l'invité à
  /// tous les participants dès qu'il décroche.
  void inviteToCall(String publicNumber) {
    final id = activeCallId;
    if (id == null) return;
    isGroupCall = true; // devient un appel de groupe
    _rt.callInvite(id, publicNumber);
    notifyListeners();
  }

  // --- Lot 4 : transfert d'appel supervisé ---
  /// Invite `publicNumber` dans l'appel puis, dès qu'il rejoint, quitte
  /// automatiquement (l'appel continue entre le correspondant et l'invité).
  void transferCall(String publicNumber) {
    final id = activeCallId;
    if (id == null) return;
    _pendingTransfer = true;
    _transferTargetId = null;
    lastError = null;
    _rt.callInvite(id, publicNumber);
    notifyListeners();
  }

  /// L'initiateur quitte SANS terminer l'appel pour les autres (transfert).
  Future<void> _completeTransfer(String callId) async {
    _pendingTransfer = false;
    _transferTargetId = null;
    activeCallId = null; // bloque les échos pendant le nettoyage
    try {
      await _calls.leave(callId);
    } catch (_) {}
    _rt.callState(callId, "left", userId: myUserId, displayName: myDisplayName);
    await _stopMesh();
    _clear();
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
      throw Exception(
          "PERMISSION_DENIED"); // ← FIX: throw au lieu de return silencieux
    }
    lastError = null;

    // Si le mesh existe déjà et le stream local est prêt, ne rien faire.
    if (_mesh != null && _mesh!.localStream != null) return;

    // FIX: utilise directement les serveurs ICE codés en dur dans l'application.
    // Plus d'appel réseau vers le backend pour récupérer /api/calls/ice.
    List<Map<String, dynamic>> ice;
    try {
      ice = await _loadIceServers();
      debugPrint(
          "[CallController] ICE servers chargés depuis le backend: ${ice.length} serveurs");
    } catch (e) {
      debugPrint(
          "[CallController] Backend ICE indisponible, fallback hardcodé: $e");
      ice = WebrtcPeerSession.fallbackIce;
    }
    // Réinitialise si la mesh précédente était en erreur
    if (_mesh == null) {
      final callId = activeCallId!;
      _mesh = WebrtcGroupMesh(
        myUserId: myUserId!,
        isVideo: isVideo,
        iceServers: ice,
        onSendSignal: (peerId, sig) => _rt.callSignal(callId, peerId, sig),
        onUpdated: _onMeshUpdated,
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
    // Rejoint alors que l'appel est DÉJÀ connecté (ongoing) → c'est un invité
    // (invitation ou transfert), pas le correspondant d'origine. On capture
    // l'état AVANT la bascule outgoing→ongoing faite plus bas.
    final joinedWhileOngoing = activeRole == ActiveCallRole.ongoing;
    if (displayName != null && displayName.isNotEmpty) {
      participantNames[userId] = displayName;
    }
    final isNew = joinedParticipantIds.add(userId);
    // Invité = rejoint un appel en cours ET n'était pas un membre initial.
    if (joinedWhileOngoing && isNew && !_initialMemberIds.contains(userId)) {
      invitedParticipantIds.add(userId);
    }
    // Transfert supervisé : la cible vient de rejoindre → l'initiateur quitte
    // automatiquement (l'appel continue entre le correspondant et l'invité).
    if (_pendingTransfer && userId == _transferTargetId) {
      final id = activeCallId;
      if (id != null) {
        await _completeTransfer(id);
        return;
      }
    }
    // Dès qu'il y a plus d'un autre participant, c'est un appel de groupe
    // (invitation dynamique) → UI grille + liste des participants.
    if (joinedParticipantIds.where((id) => id != myUserId).length > 1) {
      isGroupCall = true;
    }
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
    invitedParticipantIds.remove(userId);
    // On garde participantNames (historique) mais l'affichage se base sur
    // joinedParticipantIds → le nom du partant disparaît immédiatement.
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
        callerAvatarUrl: e["callerAvatarUrl"] as String?,
        isGroup: (e["isGroup"] as bool?) ?? false,
        groupName: e["groupName"] as String?,
        memberCount: (e["memberCount"] as num?)?.toInt() ?? 2,
      );
      // Sonnerie entrante (loop) jusqu'à accept/reject/timeout serveur.
      RingtoneService.instance.startIncoming();
      // Autorise l'écran d'appel à passer par-dessus le verrouillage, et allume
      // l'écran. Activé ICI et non au montage de l'écran d'appel : quand le
      // téléphone est verrouillé, il faut que la fenêtre porte déjà l'attribut
      // au moment où Android l'affiche.
      LockScreenCall.activer();
      notifyListeners();
    } else if (type == "call_signal") {
      final callId = e["callId"] as String?;
      final from = e["from"] as String?;
      final signal = e["signal"];
      if (callId == null || from == null || signal is! Map<String, dynamic>)
        return;
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
        // Notre propre identifiant : soit l'écho de notre « joined », soit un
        // autre appareil du même compte qui vient de décrocher — auquel cas il
        // faut couper la sonnerie ici.
        if (userId == myUserId) {
          _takenByAnotherDevice(callId);
          return;
        }
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
      } else if (state == "ringing") {
        // L'appelé signale que son écran d'appel est affiché → « En train de sonner ».
        if (userId == myUserId) return;
        if (callId == activeCallId && activeRole == ActiveCallRole.outgoing) {
          remoteRinging = true;
          notifyListeners();
        }
      } else if (state == "inviting") {
        // Un participant invite quelqu'un : l'inviteur mémorise l'identité de
        // l'invité (pour le transfert supervisé).
        if (_pendingTransfer && userId != null && userId != myUserId) {
          _transferTargetId = userId;
        }
      } else if (state == "left" || state == "declined") {
        // Notre propre départ est géré localement dans hangUp — sauf s'il vient
        // d'un autre appareil qui a refusé l'appel pendant qu'on sonne.
        if (userId == myUserId) {
          _takenByAnotherDevice(callId);
          return;
        }
        // Cible du transfert qui refuse : on annule et on reste dans l'appel.
        if (state == "declined" &&
            _pendingTransfer &&
            userId == _transferTargetId) {
          _pendingTransfer = false;
          _transferTargetId = null;
          lastError = "Transfert refusé";
          notifyListeners();
          return;
        }
        if (callId == activeCallId && userId != null) {
          _onPeerLeft(userId);
        }
      } else if (state == "rejected" || state == "ended") {
        // « ended » émis par nous-mêmes via hangUp : écho à ignorer. Mais un
        // autre appareil du même compte peut aussi avoir refusé l'appel.
        if (fromUserId == myUserId) {
          _takenByAnotherDevice(callId);
          return;
        }
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
