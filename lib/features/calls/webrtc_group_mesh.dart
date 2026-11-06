import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/debug_overlay.dart';

import 'qualite_video.dart';
import 'webrtc_peer_session.dart';

/// Mesh WebRTC : une connexion par participant distant, flux local partagé.
class WebrtcGroupMesh {
  WebrtcGroupMesh({
    required this.myUserId,
    required this.isVideo,
    required this.iceServers,
    required this.onSendSignal,
    required this.onUpdated,
    this.qualite = QualiteVideo.standard,
    MediaStream? fluxInitial,
    this.onPeerLost,
    this.onPeerReconnecting,
    this.onPeerReconnected,
  }) : _local = fluxInitial;

  /// La capture de la qualité choisie, et rien au-delà (procédure du patron,
  /// 01/11/2026). Le téléphone ne filme pas plus que ce qu'on enverra ; WebRTC
  /// baisse ensuite lui-même la qualité si le réseau faiblit.
  ///
  /// ⚠️ DES NOMBRES, PAS `{min, ideal, max}`. Sur Android, `flutter_webrtc`
  /// 0.12.12 ne lit cette forme qu'à moitié (il cherche `ideal` au mauvais
  /// niveau) et retombe sur 1280×720 à 30 images/s. Il ignore aussi `min` et
  /// `max`.
  static Map<String, dynamic> contraintesVideo(QualiteVideo q) => {
        "facingMode": "user",
        "width": q.largeur,
        "height": q.hauteur,
        "frameRate": q.cadence,
      };

  static const _contraintesAudio = {
    "echoCancellation": true,
    "noiseSuppression": true,
    "autoGainControl": true,
  };

  final String myUserId;
  final bool isVideo;
  final List<Map<String, dynamic>> iceServers;
  final void Function(String peerId, Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;

  /// La qualité de cet appel (choix de l'utilisateur, plafonné en groupe).
  final QualiteVideo qualite;

  /// Connexion média définitivement perdue avec ce pair — après que la
  /// session a épuisé ses tentatives de reprise.
  final void Function(String peerId)? onPeerLost;

  /// Le chemin vers ce pair vacille, la reprise est en cours.
  final void Function(String peerId)? onPeerReconnecting;

  /// Le média est revenu avec ce pair.
  final void Function(String peerId)? onPeerReconnected;

  MediaStream? _local;
  final Map<String, WebrtcPeerSession> _peers = {};

  /// Le réseau a changé pendant l'appel : chaque liaison se relance tout de
  /// suite (voir `WebrtcPeerSession.relancerApresChangementDeReseau`).
  /// Une liaison au moins est-elle dégradée ? → « Connexion faible ».
  bool get connexionFaible =>
      _peers.values.any((s) => s.connexionFaible.value);

  /// La caméra de [peerId] est-elle allumée ?
  bool cameraDistanteActive(String peerId) =>
      _peers[peerId]?.cameraDistanteActive ?? true;

  /// Prévient tous les pairs de l'état de notre caméra.
  void envoyerEtatCamera(bool active) {
    for (final s in _peers.values) {
      s.envoyerEtatCamera(active);
    }
  }

  /// Coupe ou rallume l'ÉMISSION de nos images sans toucher au choix de
  /// l'utilisateur ([cameraEnabled]) : l'application passe en arrière-plan.
  void suspendreVideoLocale(bool suspendue) {
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !suspendue;
    }
  }

  /// Force une image clé chez les pairs : la piste est coupée puis rallumée.
  /// Sans elle, un décodeur qui a perdu le fil attend en montrant une image
  /// figée (guide du 31/10/2026).
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

  void relancerLesLiaisons() {
    for (final s in _peers.values) {
      s.relancerApresChangementDeReseau();
    }
  }
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
  /// bascule juste leur état enabled). Le correspondant en est prévenu
  /// (31/10/2026) : il voit notre avatar, et non plus un flux figé ou noir.
  void setCamera(bool on) {
    _cameraEnabled = on;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    envoyerEtatCamera(on);
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
    /*
     * L'APERÇU DE L'APPEL ENTRANT (06/11/2026) a déjà ouvert la caméra, sans le
     * micro : ouvert pendant la sonnerie, il aurait basculé l'audio du téléphone
     * en mode communication. On lui ajoute le micro au décrochage, sans rouvrir
     * la caméra — une réouverture ferait clignoter l'image, et échoue sur
     * certains téléphones. Si l'ajout échoue, on rouvre tout.
     */
    final deja = _local;
    if (deja != null && deja.getAudioTracks().isEmpty) {
      try {
        final audio = await navigator.mediaDevices
            .getUserMedia({"audio": _contraintesAudio, "video": false});
        for (final t in audio.getAudioTracks()) {
          await deja.addTrack(t);
        }
      } catch (e) {
        traceAppel("micro non ajouté à l'aperçu ($e) → flux rouvert");
        for (final t in deja.getTracks()) {
          await t.stop();
        }
        await deja.dispose();
        _local = null;
      }
    }
    _local ??= await navigator.mediaDevices.getUserMedia({
      "audio": _contraintesAudio,
      "video": isVideo ? contraintesVideo(qualite) : false,
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
      traceAppel("connectToPeer($peerId) IGNORE — moi=${peerId == myUserId} dejaConnu=${_peers.containsKey(peerId)}");
      return;
    }
    traceAppel("connectToPeer($peerId) — jeSuisOffreur=$asOfferer");
    await ensureLocal();
    final session = WebrtcPeerSession(
      peerId: peerId,
      isVideo: isVideo,
      isOfferer: asOfferer,
      localStream: _local!,
      iceServers: iceServers,
      onSendSignal: (sig) => onSendSignal(peerId, sig),
      onUpdated: onUpdated,
      debitVideoMax: qualite.debitMax,
      cadenceVideoMax: qualite.cadence,
      hauteurCapture: qualite.hauteur,
      onConnectionLost: () => onPeerLost?.call(peerId),
      onReconnecting: () => onPeerReconnecting?.call(peerId),
      onReconnected: () => onPeerReconnected?.call(peerId),
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
    // Décroché caméra coupée : le pair qui arrive doit le savoir tout de suite,
    // sinon il attend une image qui ne viendra pas (06/11/2026).
    if (isVideo && !_cameraEnabled) session.envoyerEtatCamera(false);
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
      traceAppel("OFFRE de $fromPeerId sans session → ouverture immediate");
      await connectToPeer(fromPeerId, asOfferer: false);
      session = _peers[fromPeerId];
    }

    if (session == null) {
      traceAppel("mesh.handleSignal ${signal["kind"]} de $fromPeerId → MIS EN ATTENTE (pas de session)");
      _pendingByPeer.putIfAbsent(fromPeerId, () => []).add(signal);
      return;
    }
    traceAppel("mesh.handleSignal ${signal["kind"]} de $fromPeerId → session");
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
