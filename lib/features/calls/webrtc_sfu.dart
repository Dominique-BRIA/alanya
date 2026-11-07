import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/authed_api.dart';
import '../../core/debug_overlay.dart';
import 'moteur_media.dart';
import 'qualite_video.dart';
import 'webrtc_group_mesh.dart';
import 'webrtc_peer_session.dart';

/// Les routes `/api/sfu/...` du serveur, qui seul parle à Cloudflare : le
/// jeton de l'application SFU ne quitte jamais le serveur.
class SfuApi {
  SfuApi(this._api);
  final AuthedApi _api;

  Future<String> creerSession(String salle) async {
    final d = await _api.post("/api/sfu/sessions", {"salle": salle});
    return d["sessionId"] as String;
  }

  /// → la réponse de Cloudflare à notre offre.
  Future<String> publier(String sessionId, String offreSdp, List<Map<String, String>> pistes) async {
    final d = await _api.post("/api/sfu/sessions/$sessionId/publier", {
      "offre": {"type": "offer", "sdp": offreSdp},
      "pistes": pistes,
    });
    return ((d["reponse"] as Map?)?["sdp"] as String?) ?? "";
  }

  /// → l'offre de Cloudflare (ou `null`) et, pour chaque piste, son `mid`.
  Future<({String? offre, List<({String mid, String userId, String nom})> pistes})> recevoir(
    String sessionId,
    List<({String userId, String nom})> pistes,
  ) async {
    final d = await _api.post("/api/sfu/sessions/$sessionId/recevoir", {
      "pistes": [for (final p in pistes) {"userId": p.userId, "nom": p.nom}],
    });
    final offre = (d["offre"] as Map?)?["sdp"] as String?;
    final liste = <({String mid, String userId, String nom})>[];
    for (final p in (d["pistes"] as List?) ?? const []) {
      final m = p as Map;
      liste.add((mid: "${m["mid"]}", userId: "${m["userId"]}", nom: "${m["nom"]}"));
    }
    return (offre: offre, pistes: liste);
  }

  Future<void> renegocier(String sessionId, String reponseSdp) async {
    await _api.put("/api/sfu/sessions/$sessionId/renegocier", {
      "reponse": {"type": "answer", "sdp": reponseSdp},
    });
  }

  /// → une offre de Cloudflare à laquelle répondre, ou `null`.
  Future<String?> fermer(String sessionId, List<String> mids) async {
    final d = await _api.post("/api/sfu/sessions/$sessionId/fermer", {"mids": mids});
    return (d["offre"] as Map?)?["sdp"] as String?;
  }

  Future<void> raccrocher(String sessionId) async {
    await _api.post("/api/sfu/sessions/$sessionId/fermer", {"tout": true});
  }

  /// Ce que les AUTRES publient déjà dans la salle.
  Future<List<({String userId, String nom, String genre})>> pistesDeLaSalle(String salle) async {
    final d = await _api.get("/api/sfu/salles/${Uri.encodeComponent(salle)}/pistes");
    return [
      for (final p in (d["pistes"] as List?) ?? const [])
        (
          userId: "${(p as Map)["userId"]}",
          nom: "${p["nom"]}",
          genre: "${p["genre"]}",
        ),
    ];
  }
}

/// LE MOTEUR SFU (07/11/2026) — le SFU de Cloudflare, pour les appels de
/// groupe et les réunions.
///
/// UNE seule connexion WebRTC, vers Cloudflare :
///  1. on y PUBLIE nos pistes (micro, caméra) : notre offre, sa réponse ;
///  2. le serveur prévient les autres (trame `sfu_pistes`), qui viennent les
///     chercher ; nous faisons de même pour les leurs ([surPistes], et la
///     liste de la salle en arrivant) : Cloudflare rend alors SON offre, à
///     laquelle nous répondons.
///
/// Chaque piste reçue arrive sous un `mid` que le serveur nous a donné avec
/// le nom de son auteur : c'est ce qui rattache chaque voix et chaque image à
/// un participant.
///
/// ⚠️ LES NÉGOCIATIONS PASSENT UNE PAR UNE ([_enFile]). Une connexion WebRTC ne
/// supporte qu'une négociation à la fois : une publication et une réception
/// qui se croisent laisseraient la connexion dans un état incohérent.
///
/// Ce qui ne change pas par rapport au mesh : les petits messages de contrôle
/// (caméra coupée, passage en vidéo) passent toujours par le socket, de pair
/// à pair ([onSendSignal]).
class WebrtcSfu implements MoteurMedia {
  WebrtcSfu({
    required this.myUserId,
    required this.isVideo,
    required this.iceServers,
    required this.salle,
    required this.api,
    required this.onSendSignal,
    required this.onUpdated,
    this.qualite = QualiteVideo.standard,
    MediaStream? fluxInitial,
    this.onPeerLost,
    this.onPeerReconnecting,
    this.onPeerReconnected,
    this.onPeerPassageVideo,
  }) : _local = fluxInitial;

  final String myUserId;
  @override
  bool isVideo;
  final List<Map<String, dynamic>> iceServers;

  /// `call:<id>` ou `meeting:<id>`.
  final String salle;
  final SfuApi api;
  final void Function(String peerId, Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;
  final QualiteVideo qualite;
  final void Function(String peerId)? onPeerLost;
  final void Function(String peerId)? onPeerReconnecting;
  final void Function(String peerId)? onPeerReconnected;
  final void Function(String peerId)? onPeerPassageVideo;

  MediaStream? _local;
  RTCPeerConnection? _pc;
  String? _sessionId;
  bool _ferme = false;

  /// Les participants que l'appel nous a présentés ([connectToPeer]).
  final Set<String> _pairs = {};

  /// Ceux qui sont partis ([removePeer]) : on ne va plus chercher leurs pistes.
  final Set<String> _partis = {};

  /// Ce que chacun publie, par nom de piste → genre (« audio », « video »).
  final Map<String, Map<String, String>> _publiees = {};

  /// Les pistes reçues : `mid` → auteur, et auteur → (nom → `mid`).
  final Map<String, String> _auteurDuMid = {};
  final Map<String, Map<String, String>> _midsDe = {};

  /// Le flux affiché pour chacun : celui qui porte sa vidéo s'il en a une.
  final Map<String, MediaStream> _flux = {};
  final Map<String, MediaStream> _fluxAudio = {};
  final Map<String, bool> _cameraDistante = {};

  /// Les noms des pistes que nous publions (uniques dans notre session).
  final Set<String> _nosPistes = {};
  int _numeroPiste = 0;

  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _connexionFaible = false;
  int _reprises = 0;

  Future<void> _file = Future.value();

  // ── Ce que voient les contrôleurs ─────────────────────────────────────────

  @override
  MediaStream? get localStream => _local;
  @override
  Map<String, MediaStream> get remoteStreams => Map.unmodifiable(_flux);
  @override
  int get connectedCount => _flux.length;
  @override
  Set<String> get peerIds => {..._pairs, ..._flux.keys};
  @override
  bool get micEnabled => _micEnabled;
  @override
  bool get cameraEnabled => _cameraEnabled;
  @override
  bool get aUneCamera => _local?.getVideoTracks().isNotEmpty ?? false;
  @override
  bool get connexionFaible => _connexionFaible;
  @override
  bool cameraDistanteActive(String peerId) => _cameraDistante[peerId] ?? true;

  /// Les petits messages de contrôle vont à tous ceux qu'on connaît.
  Set<String> get _destinataires => {..._pairs, ..._publiees.keys}..remove(myUserId);

  // ── File des négociations ─────────────────────────────────────────────────

  Future<T> _enFile<T>(Future<T> Function() operation) {
    final fait = Completer<T>();
    _file = _file.then((_) async {
      try {
        fait.complete(await operation());
      } catch (e, pile) {
        fait.completeError(e, pile);
      }
    });
    return fait.future;
  }

  // ── Média local ───────────────────────────────────────────────────────────

  static const _contraintesAudio = {
    "echoCancellation": true,
    "noiseSuppression": true,
    "autoGainControl": true,
  };

  /// Ouvre le micro (et la caméra en vidéo), puis la connexion au SFU, où nos
  /// pistes sont publiées. Une erreur remonte : le contrôleur la traite comme
  /// un échec du mesh (« Connexion WebRTC impossible »).
  @override
  Future<void> ensureLocal() async {
    final deja = _local;
    if (deja != null && deja.getAudioTracks().isEmpty) {
      // L'aperçu de l'appel entrant n'a ouvert que la caméra.
      try {
        final audio = await navigator.mediaDevices.getUserMedia({"audio": _contraintesAudio, "video": false});
        for (final t in audio.getAudioTracks()) {
          await deja.addTrack(t);
        }
      } catch (e) {
        traceAppel("SFU : micro non ajouté à l'aperçu ($e) → flux rouvert");
        for (final t in deja.getTracks()) {
          await t.stop();
        }
        await deja.dispose();
        _local = null;
      }
    }
    _local ??= await navigator.mediaDevices.getUserMedia({
      "audio": _contraintesAudio,
      "video": isVideo ? WebrtcGroupMesh.contraintesVideo(qualite) : false,
    });
    onUpdated();
    if (_pc == null) await _enFile(_connecter);
  }

  Future<void> _connecter() async {
    if (_ferme || _pc != null) return;
    final sessionId = await api.creerSession(salle);
    final raw = iceServers.isNotEmpty ? iceServers : WebrtcPeerSession.fallbackIce;
    final pc = await createPeerConnection({
      // Le STUN de Cloudflare d'abord : c'est vers son réseau que l'on va.
      "iceServers": [
        {"urls": "stun:stun.cloudflare.com:3478"},
        ...WebrtcPeerSession.normalizeIceServers(raw),
      ],
      "bundlePolicy": "max-bundle",
      "rtcpMuxPolicy": "require",
      "sdpSemantics": "unified-plan",
    });
    pc.onTrack = _surPisteRecue;
    pc.onConnectionState = _surEtatConnexion;
    _pc = pc;
    _sessionId = sessionId;
    traceAppel("SFU : session ouverte pour $salle");

    final local = _local;
    if (local != null) {
      await _publierLocal([...local.getAudioTracks(), ...local.getVideoTracks()]);
    }
    // Ceux qui publient déjà : personne ne nous les annoncera.
    try {
      final deja = await api.pistesDeLaSalle(salle);
      for (final p in deja) {
        _publiees.putIfAbsent(p.userId, () => {})[p.nom] = p.genre;
      }
      final aRecevoir = [
        for (final p in deja)
          if (!_partis.contains(p.userId)) (userId: p.userId, nom: p.nom),
      ];
      if (aRecevoir.isNotEmpty) await _recevoir(aRecevoir);
    } catch (e) {
      traceAppel("SFU : pistes de la salle illisibles ($e)");
    }
  }

  /// Publie [pistes] : une transceiver « envoi seul » chacune, notre offre,
  /// la réponse de Cloudflare.
  Future<void> _publierLocal(List<MediaStreamTrack> pistes) async {
    final pc = _pc;
    final sessionId = _sessionId;
    final local = _local;
    if (pc == null || sessionId == null || local == null || pistes.isEmpty) return;

    final noms = <String, String>{}; // id de la piste → nom publié
    for (final t in pistes) {
      await pc.addTransceiver(
        track: t,
        kind: t.kind == "video" ? RTCRtpMediaType.RTCRtpMediaTypeVideo : RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [local]),
      );
      final base = t.kind == "video" ? "video" : "audio";
      var nom = base;
      while (_nosPistes.contains(nom)) {
        nom = "$base${++_numeroPiste}";
      }
      _nosPistes.add(nom);
      noms[t.id ?? nom] = nom;
    }
    final offre = await pc.createOffer();
    await pc.setLocalDescription(offre);

    final declarees = <Map<String, String>>[];
    for (final tr in await pc.getTransceivers()) {
      final piste = tr.sender.track;
      final nom = piste == null ? null : noms[piste.id];
      if (nom == null || tr.mid.isEmpty) continue;
      declarees.add({"mid": tr.mid, "nom": nom, "genre": piste!.kind == "video" ? "video" : "audio"});
    }
    final locale = await pc.getLocalDescription();
    final reponse = await api.publier(sessionId, locale?.sdp ?? offre.sdp ?? "", declarees);
    await pc.setRemoteDescription(RTCSessionDescription(reponse, "answer"));
    await _reglerEmission();
    traceAppel("SFU : publié ${declarees.map((d) => d["nom"]).join(", ")}");
  }

  /// Son prioritaire, vidéo plafonnée à la qualité de l'appel — comme le mesh.
  Future<void> _reglerEmission() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      for (final emetteur in await pc.getSenders()) {
        final nature = emetteur.track?.kind;
        if (nature == null) continue;
        final parametres = emetteur.parameters;
        if (parametres.encodings == null || parametres.encodings!.isEmpty) {
          parametres.encodings = [RTCRtpEncoding()];
        }
        for (final e in parametres.encodings!) {
          if (nature == "audio") {
            e.priority = RTCPriorityType.high;
            e.networkPriority = RTCPriorityType.high;
          } else {
            e.maxBitrate = qualite.debitMax;
            e.maxFramerate = qualite.cadence;
            e.priority = RTCPriorityType.low;
            e.networkPriority = RTCPriorityType.low;
          }
        }
        if (nature == "video") {
          parametres.degradationPreference = RTCDegradationPreference.BALANCED;
        }
        await emetteur.setParameters(parametres);
      }
    } catch (e) {
      traceAppel("SFU : réglage de l'émission impossible — $e");
    }
  }

  /// Va chercher [pistes] chez Cloudflare. Les `mid` sont notés AVANT
  /// d'appliquer l'offre : les pistes arrivent pendant `setRemoteDescription`.
  Future<void> _recevoir(List<({String userId, String nom})> pistes) async {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || pistes.isEmpty) return;
    final r = await api.recevoir(sessionId, pistes);
    for (final p in r.pistes) {
      _auteurDuMid[p.mid] = p.userId;
      _midsDe.putIfAbsent(p.userId, () => {})[p.nom] = p.mid;
    }
    final offre = r.offre;
    if (offre == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(offre, "offer"));
    final reponse = await pc.createAnswer();
    await pc.setLocalDescription(reponse);
    await api.renegocier(sessionId, reponse.sdp ?? "");
    traceAppel("SFU : reçu ${r.pistes.map((p) => "${p.userId}/${p.nom}").join(", ")}");
  }

  void _surPisteRecue(RTCTrackEvent e) {
    final mid = e.transceiver?.mid;
    final auteur = mid == null ? null : _auteurDuMid[mid];
    if (auteur == null) {
      traceAppel("SFU : piste reçue sans auteur connu (mid=$mid)");
      return;
    }
    unawaited(_rangerPiste(auteur, e.track, e.streams));
  }

  /// Range la piste de [auteur] dans SON flux. Cloudflare peut livrer la voix
  /// et l'image d'une même personne dans deux flux distincts : on les réunit,
  /// pour que l'écran n'ait qu'un flux par participant, comme en mesh.
  Future<void> _rangerPiste(String auteur, MediaStreamTrack piste, List<MediaStream> flux) async {
    var cible = _flux[auteur];
    if (cible == null) {
      cible = flux.isNotEmpty ? flux.first : await createLocalMediaStream("sfu-$auteur");
      _flux[auteur] = cible;
    }
    final dejaDedans = cible.getTracks().any((t) => t.id == piste.id);
    if (!dejaDedans) {
      try {
        await cible.addTrack(piste);
      } catch (e) {
        // Certaines versions refusent d'ajouter une piste distante à un flux
        // créé localement : on garde alors un flux par genre.
        traceAppel("SFU : piste ${piste.kind} de $auteur gardée à part ($e)");
        if (piste.kind == "audio") {
          _fluxAudio[auteur] = flux.isNotEmpty ? flux.first : cible;
        } else if (flux.isNotEmpty) {
          _flux[auteur] = flux.first;
        }
      }
    }
    onPeerReconnected?.call(auteur);
    onUpdated();
  }

  void _surEtatConnexion(RTCPeerConnectionState etat) {
    traceAppel("SFU : connexion $etat");
    switch (etat) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reprises = 0;
        if (_connexionFaible) {
          _connexionFaible = false;
          for (final p in _destinataires) {
            onPeerReconnected?.call(p);
          }
          onUpdated();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _connexionFaible = true;
        for (final p in _destinataires) {
          onPeerReconnecting?.call(p);
        }
        onUpdated();
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        unawaited(_reprendre());
      default:
        break;
    }
  }

  /// La connexion au SFU est perdue : on en ouvre une nouvelle, on republie
  /// et l'on va rechercher les pistes de chacun. Trois essais, puis l'appel
  /// est déclaré perdu pour tous.
  Future<void> _reprendre() async {
    if (_ferme) return;
    if (_reprises >= 3) {
      for (final p in _destinataires) {
        onPeerLost?.call(p);
      }
      return;
    }
    _reprises++;
    _connexionFaible = true;
    for (final p in _destinataires) {
      onPeerReconnecting?.call(p);
    }
    onUpdated();
    await _enFile(() async {
      final ancienne = _pc;
      final ancienneSession = _sessionId;
      _pc = null;
      _sessionId = null;
      _auteurDuMid.clear();
      _midsDe.clear();
      _nosPistes.clear();
      await ancienne?.close();
      if (ancienneSession != null) unawaited(api.raccrocher(ancienneSession).catchError((_) {}));
      try {
        await _connecter();
      } catch (e) {
        traceAppel("SFU : reprise $_reprises impossible ($e)");
      }
    });
  }

  // ── Participants ──────────────────────────────────────────────────────────

  @override
  Future<void> connectToPeer(String peerId, {required bool asOfferer}) async {
    if (peerId == myUserId) return;
    final nouveau = _pairs.add(peerId);
    final revenu = _partis.remove(peerId);
    await ensureLocal();
    // Décroché caméra coupée : le nouveau venu doit le savoir tout de suite.
    if (nouveau && isVideo && !_cameraEnabled) {
      onSendSignal(peerId, {"kind": "camera_state", "enabled": false});
    }
    // Revenu après un départ : ses pistes ont pu être annoncées pendant son
    // absence, on va les chercher.
    final connues = _publiees[peerId];
    if (revenu && connues != null && connues.isNotEmpty) {
      await _enFile(() => _recevoir([for (final nom in connues.keys) (userId: peerId, nom: nom)]));
    }
  }

  /// Trame `sfu_pistes` : [userId] vient de publier des pistes dans [salle].
  /// Une nouvelle annonce remplace la précédente (il a pu se reconnecter avec
  /// une nouvelle session) : les anciennes réceptions sont fermées d'abord.
  Future<void> surPistes(Map<String, dynamic> trame) async {
    if (_ferme || trame["salle"] != salle) return;
    final auteur = "${trame["userId"]}";
    if (auteur.isEmpty || auteur == myUserId) return;
    final pistes = <({String userId, String nom})>[];
    for (final p in (trame["pistes"] as List?) ?? const []) {
      final m = p as Map;
      final nom = "${m["nom"]}";
      _publiees.putIfAbsent(auteur, () => {})[nom] = "${m["genre"]}";
      pistes.add((userId: auteur, nom: nom));
    }
    if (pistes.isEmpty || _partis.contains(auteur)) return;
    await _enFile(() async {
      final anciens = <String>[];
      for (final p in pistes) {
        final mid = _midsDe[auteur]?.remove(p.nom);
        if (mid != null) {
          _auteurDuMid.remove(mid);
          anciens.add(mid);
        }
      }
      if (anciens.isNotEmpty) await _fermerMids(anciens);
      await _recevoir(pistes);
    });
  }

  Future<void> _fermerMids(List<String> mids) async {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || mids.isEmpty) return;
    try {
      final offre = await api.fermer(sessionId, mids);
      if (offre != null) {
        await pc.setRemoteDescription(RTCSessionDescription(offre, "offer"));
        final reponse = await pc.createAnswer();
        await pc.setLocalDescription(reponse);
        await api.renegocier(sessionId, reponse.sdp ?? "");
      }
    } catch (e) {
      traceAppel("SFU : fermeture de pistes impossible ($e)");
    }
  }

  @override
  Future<void> handleSignal(String fromPeerId, Map<String, dynamic> signal) async {
    switch (signal["kind"]) {
      case "camera_state":
        _cameraDistante[fromPeerId] = signal["enabled"] != false;
        onUpdated();
      case "video_upgrade":
        onPeerPassageVideo?.call(fromPeerId);
      default:
        // Offre, réponse, candidat ICE : rien de pair à pair en SFU.
        break;
    }
  }

  @override
  Future<void> removePeer(String peerId) async {
    _pairs.remove(peerId);
    _partis.add(peerId);
    _cameraDistante.remove(peerId);
    final flux = _flux.remove(peerId);
    _fluxAudio.remove(peerId);
    final mids = _midsDe.remove(peerId)?.values.toList() ?? const <String>[];
    for (final m in mids) {
      _auteurDuMid.remove(m);
    }
    onUpdated();
    if (flux != null && flux.id.startsWith("sfu-")) {
      unawaited(flux.dispose().catchError((_) {}));
    }
    if (mids.isNotEmpty) await _enFile(() => _fermerMids(mids));
  }

  // ── Contrôles locaux ──────────────────────────────────────────────────────

  @override
  void setMic(bool on) {
    _micEnabled = on;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    onUpdated();
  }

  @override
  void setCamera(bool on) {
    _cameraEnabled = on;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    envoyerEtatCamera(on);
    onUpdated();
  }

  @override
  Future<void> switchCamera() async {
    final pistes = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (pistes.isEmpty) return;
    await Helper.switchCamera(pistes.first);
  }

  @override
  void envoyerEtatCamera(bool active) {
    for (final p in _destinataires) {
      onSendSignal(p, {"kind": "camera_state", "enabled": active});
    }
  }

  @override
  void suspendreVideoLocale(bool suspendue) {
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !suspendue;
    }
  }

  @override
  Future<void> rafraichirVideoLocale() async {
    final pistes = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    for (final t in pistes) {
      t.enabled = false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final t in pistes) {
      t.enabled = true;
    }
  }

  /// Passe en vidéo : la caméra est ouverte et PUBLIÉE comme une piste de
  /// plus ; les autres la reçoivent par la trame `sfu_pistes`.
  @override
  Future<void> passerEnVideo({required bool camera, bool annoncer = false}) async {
    isVideo = true;
    final local = _local;
    if (!camera || local == null) {
      _cameraEnabled = false;
      onUpdated();
      return;
    }
    var piste = local.getVideoTracks().isEmpty ? null : local.getVideoTracks().first;
    if (piste == null) {
      final fluxCamera = await navigator.mediaDevices
          .getUserMedia({"audio": false, "video": WebrtcGroupMesh.contraintesVideo(qualite)});
      piste = fluxCamera.getVideoTracks().first;
      await local.addTrack(piste);
      if (annoncer) {
        for (final p in _destinataires) {
          onSendSignal(p, {"kind": "video_upgrade"});
        }
      }
      final nouvelle = piste;
      await _enFile(() => _publierLocal([nouvelle]));
    }
    piste.enabled = true;
    _cameraEnabled = true;
    envoyerEtatCamera(true);
    onUpdated();
  }

  @override
  void relancerLesLiaisons() {
    // Le réseau a changé : une relance ICE ne suffit pas toujours vers un
    // SFU, on rouvre la connexion — sauf si elle tient encore.
    final etat = _pc?.connectionState;
    if (etat == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
    unawaited(_reprendre());
  }

  // ── Qui parle ─────────────────────────────────────────────────────────────

  @override
  Future<Map<String, double>?> niveauxAudio(String moiCle) async {
    final pc = _pc;
    if (pc == null) return null;
    final niveaux = <String, double>{};
    final rapports = await pc.getStats();
    for (final r in rapports) {
      final v = r.values;
      if (v['kind'] != 'audio') continue;
      final niveau = (v['audioLevel'] as num?)?.toDouble();
      if (niveau == null) continue;
      if (r.type == 'inbound-rtp') {
        final auteur = _auteurDuMid["${v['mid']}"];
        if (auteur != null) niveaux[auteur] = niveau;
      } else if (r.type == 'media-source') {
        niveaux[moiCle] = niveau;
      }
    }
    return niveaux;
  }

  // ── Fin ───────────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    _ferme = true;
    final session = _sessionId;
    _sessionId = null;
    if (session != null) unawaited(api.raccrocher(session).catchError((_) {}));
    await _pc?.close();
    _pc = null;
    for (final f in _flux.values) {
      if (f.id.startsWith("sfu-")) await f.dispose().catchError((_) {});
    }
    _flux.clear();
    _fluxAudio.clear();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
  }
}
