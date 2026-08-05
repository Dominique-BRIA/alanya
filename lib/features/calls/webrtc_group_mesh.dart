import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'webrtc_peer_session.dart';

/// Mesh WebRTC : une connexion par participant distant, flux local partagé.
class WebrtcGroupMesh {
  WebrtcGroupMesh({
    required this.myUserId,
    required this.isVideo,
    required this.iceServers,
    required this.onSendSignal,
    required this.onUpdated,
  });

  final String myUserId;
  final bool isVideo;
  final List<Map<String, dynamic>> iceServers;
  final void Function(String peerId, Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;

  MediaStream? _local;
  final Map<String, WebrtcPeerSession> _peers = {};
  final Map<String, List<Map<String, dynamic>>> _pendingByPeer = {};

  MediaStream? get localStream => _local;
  Map<String, MediaStream> get remoteStreams => {
        for (final e in _peers.entries)
          if (e.value.remoteStream != null) e.key: e.value.remoteStream!,
      };
  int get connectedCount => remoteStreams.length;
  Set<String> get peerIds => _peers.keys.toSet();

  // --- Contrôles média locaux ---
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool get micEnabled => _micEnabled;
  bool get cameraEnabled => _cameraEnabled;

  /// Active/coupe le micro (mute/unmute) sans renégocier : on désactive juste
  /// les pistes audio locales.
  void setMic(bool on) {
    _micEnabled = on;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    onUpdated();
  }

  /// Active/coupe la caméra locale (les pistes vidéo restent négociées, on
  /// bascule juste leur état enabled — le correspondant voit un flux figé/noir).
  void setCamera(bool on) {
    _cameraEnabled = on;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    onUpdated();
  }

  /// Bascule caméra avant/arrière sur la piste vidéo locale.
  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  // NOTE — le rôle d'offreur ne se déduit PLUS des identifiants.
  //
  // L'ancienne règle (`myId.compareTo(peerId) < 0`) désignait toujours le même
  // offreur pour une paire donnée, quel que soit le sens de l'appel. Quand elle
  // désignait l'appelé, l'offre dépendait de la liste renvoyée par `/accept` et
  // du vidage d'un tampon, là où l'appelant, lui, l'émet directement. Résultat :
  // pour deux personnes données, un sens marchait toujours et l'autre jamais.
  //
  // La règle retenue est POSITIONNELLE : celui qui est DÉJÀ dans l'appel offre
  // à celui qui ARRIVE. Elle se lit directement dans l'événement reçu — je
  // découvre les présents en entrant (je n'offre pas, ils m'offriront) ou je
  // vois quelqu'un entrer (j'offre). En 1-à-1 cela revient à « l'appelant
  // offre », et aucune collision n'est possible puisque les deux rôles sont
  // toujours attribués par des événements différents.

  Future<void> ensureLocal() async {
    _local ??= await navigator.mediaDevices.getUserMedia({
      "audio": true,
      "video": isVideo,
    });
    onUpdated();
  }

  /// Ouvre la connexion vers [peerId].
  ///
  /// [asOfferer] dit qui émet l'offre, et ce choix appartient à l'appelant :
  /// `false` quand je découvre quelqu'un déjà présent (il m'offrira), `true`
  /// quand je le vois arriver après moi.
  Future<void> connectToPeer(String peerId, {required bool asOfferer}) async {
    if (peerId == myUserId || _peers.containsKey(peerId)) {
      debugPrint(
          "[APPEL] connectToPeer($peerId) IGNORE — moi=${peerId == myUserId} dejaConnu=${_peers.containsKey(peerId)}");
      return;
    }
    debugPrint("[APPEL] connectToPeer($peerId) — jeSuisOffreur=$asOfferer");
    await ensureLocal();
    final session = WebrtcPeerSession(
      peerId: peerId,
      isVideo: isVideo,
      isOfferer: asOfferer,
      localStream: _local!,
      iceServers: iceServers,
      onSendSignal: (sig) => onSendSignal(peerId, sig),
      onUpdated: onUpdated,
    );
    _peers[peerId] = session;

    // Les signaux reçus AVANT l'existence de la session sont les plus anciens :
    // on les redonne avant `start()`, pas après. La session n'étant pas encore
    // prête, ils rejoignent sa file et seront rejoués dans l'ordre d'arrivée,
    // devant ceux qui tomberont pendant le démarrage. Les injecter après
    // inversait l'ordre et pouvait présenter un candidat ICE avant son offre.
    final buffered = _pendingByPeer.remove(peerId) ?? [];
    for (final sig in buffered) {
      await session.handleSignal(sig);
    }

    await session.start();
  }

  Future<void> handleSignal(String fromPeerId, Map<String, dynamic> signal) async {
    var session = _peers[fromPeerId];

    // Une OFFRE reçue d'un inconnu ouvre la connexion séance tenante, au lieu
    // d'attendre l'événement d'adhésion qui devait la créer. Cette attente
    // était le maillon fragile : si l'événement se perdait, arrivait trop tôt
    // ou trouvait le tampon déjà vidé, l'offre n'était jamais traitée et la
    // négociation ne démarrait pas. Recevoir une offre suffit à savoir quoi
    // faire — je réponds, donc je n'offre pas.
    if (session == null && signal["kind"] == "offer") {
      debugPrint(
          "[APPEL] OFFRE de $fromPeerId sans session → ouverture immediate");
      await connectToPeer(fromPeerId, asOfferer: false);
      session = _peers[fromPeerId];
    }

    if (session == null) {
      debugPrint(
          "[APPEL] mesh.handleSignal ${signal["kind"]} de $fromPeerId → MIS EN ATTENTE (pas de session)");
      _pendingByPeer.putIfAbsent(fromPeerId, () => []).add(signal);
      return;
    }
    debugPrint("[APPEL] mesh.handleSignal ${signal["kind"]} de $fromPeerId → session");
    await session.handleSignal(signal);
  }

  Future<void> removePeer(String peerId) async {
    await _peers.remove(peerId)?.close();
    _pendingByPeer.remove(peerId);
    onUpdated();
  }

  Future<void> close() async {
    for (final s in _peers.values) {
      await s.close();
    }
    _peers.clear();
    _pendingByPeer.clear();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
  }
}
