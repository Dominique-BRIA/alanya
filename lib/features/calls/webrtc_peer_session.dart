import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/debug_overlay.dart';

/// Connexion WebRTC vers un seul pair (utilisée par le mesh de groupe).
class WebrtcPeerSession {
  WebrtcPeerSession({
    required this.peerId,
    required this.isVideo,
    required this.isOfferer,
    required this.localStream,
    required this.iceServers,
    required this.onSendSignal,
    required this.onUpdated,
    this.onConnectionLost,
    this.onReconnecting,
    this.onReconnected,
  });

  final String peerId;
  final bool isVideo;
  final bool isOfferer;
  final MediaStream localStream;
  final List<Map<String, dynamic>> iceServers;
  final void Function(Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;

  /// Connexion avec ce pair définitivement perdue. Au contrôleur de décider :
  /// dernier pair → fin d'appel ; sinon simple retrait du participant.
  ///
  /// ⚠️ N'EST PLUS APPELÉ À LA PREMIÈRE SECOUSSE : la session tente d'abord de
  /// rerétablir le chemin réseau, et ne déclare la perte qu'après avoir épuisé
  /// ses tentatives.
  final VoidCallback? onConnectionLost;

  /// La connexion vacille et la reprise commence — de quoi afficher
  /// « Reconnexion… » sans rien couper.
  final VoidCallback? onReconnecting;

  /// Le média est repassé : l'appel reprend son cours ordinaire.
  final VoidCallback? onReconnected;

  /// Sursis accordé à un `disconnected` avant de tenter quoi que ce soit.
  ///
  /// Un réseau mobile qui change de cellule passe régulièrement par cet état
  /// puis revient de lui-même. Rerétablir aussitôt coûterait une négociation
  /// pour rien ; `failed`, lui, ne revient jamais seul et n'attend pas.
  Timer? _graceTimer;

  /*
   * 🔴 ON RÉPARE LE CHEMIN, ON NE RACCROCHE PLUS (chantier du 23/09/2026).
   *
   * Avant : `disconnected` laissait six secondes, puis la connexion était
   * déclarée perdue et l'appel tombait ; `failed` tombait sur-le-champ. Aucune
   * tentative de réparation nulle part — or c'est précisément ce que WebRTC
   * sait faire : une offre marquée `iceRestart` refait la collecte de
   * candidats et retrouve un chemin, sans toucher aux pistes ni au son déjà
   * négociés.
   *
   * ⚠️ UNE SEULE REPRISE EN VOL, ET C'EST L'OFFREUR QUI LA MÈNE. Si les deux
   * côtés relançaient une offre en même temps, chacun recevrait l'offre de
   * l'autre alors qu'il attend une réponse à la sienne — c'est le « glare »,
   * et la négociation échoue des deux côtés. Celui qui n'est pas offreur
   * demande donc la reprise à l'autre, au lieu de la faire.
   *
   * ⚠️ LE PLAFOND EST CELUI DU SERVEUR. Il tient l'appel ouvert 45 s ; au-delà
   * il le clôt de son côté. S'acharner plus longtemps ne ferait que laisser un
   * écran d'appel devant quelqu'un dont l'appel n'existe plus.
   */
  /*
   * ⚠️ DES ESSAIS ÉTALÉS SUR TOUTE LA FENÊTRE DU SERVEUR (31/10/2026). Ils
   * étaient trois, à 2, 4 et 8 s : environ 15 s, quand le serveur en accorde
   * 45. Un passage Wi-Fi → 4G, ou une cellule qui sature, dure souvent plus :
   * l'appel était déclaré perdu alors qu'il restait 30 s pour le sauver.
   */
  static const _essaisReprise = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
    Duration(seconds: 5),
    Duration(seconds: 6),
    Duration(seconds: 8),
    Duration(seconds: 8),
    Duration(seconds: 8),
  ];
  static const _plafondReprise = Duration(seconds: 45);

  /// Une offre de reprise sans réponse au-delà, on la retire (rollback) pour
  /// pouvoir en envoyer une autre : sinon, toutes les tentatives suivantes
  /// attendaient une réponse qui ne viendrait plus.
  static const _offreSansReponseMax = Duration(seconds: 8);
  DateTime? _offreEnvoyeeLe;

  /// La reprise a-t-elle été annoncée (« Reconnexion… ») ? Une reprise lancée
  /// par précaution — réseau changé, demande du pair — reste silencieuse tant
  /// que notre propre liaison n'a rien signalé.
  bool _repriseAnnoncee = false;

  /*
   * 🔴 LE RÉGLAGE DE L'ÉMISSION (31/10/2026, « que l'appel continue même
   * quand le réseau dérange »).
   *
   * - LE SON D'ABORD : priorité haute sur la piste audio, basse sur la vidéo.
   *   Sur un lien saturé, c'est la voix qui doit passer.
   * - LA VIDÉO PLAFONNÉE : sur un réseau mobile, le débit montant est le
   *   goulot ; sans plafond, l'encodeur remplit les files d'attente du
   *   réseau, et l'image se fige au lieu de baisser en qualité.
   * - « BALANCED » : sous contrainte, l'encodeur baisse à la fois la
   *   définition et la cadence, plutôt que de figer l'une pour garder l'autre.
   */
  static const _debitVideoMax = 800 * 1000;
  static const _debitVideoMin = 150 * 1000;
  static const _cadenceVideoMax = 30;
  bool _emissionReglee = false;

  /*
   * 🔴 L'ADAPTATION PAR LES STATISTIQUES (guide du patron, 31/10/2026).
   *
   * Toutes les 3 s, la session relit ses statistiques : pertes de paquets
   * (dans les deux sens), aller-retour, débit montant disponible. Réseau
   * dégradé deux fois de suite (6 s) : la vidéo passe à moitié de définition
   * et 300 kbit/s, AVANT que l'image ne se fige — et l'écran dit « Connexion
   * faible ». Trois mesures saines de suite (9 s) : on remonte. Le décalage
   * entre les deux seuils évite de faire le yo-yo sur un réseau limite.
   */
  static const _debitVideoFaible = 300 * 1000;
  static const _perteMax = 0.05;
  static const _allerRetourMax = 0.6;
  static const _debitDisponibleMin = 250 * 1000;
  Timer? _mesure;
  int _mauvaisesDeSuite = 0;
  int _bonnesDeSuite = 0;
  int _recusAvant = 0;
  int _perdusAvant = 0;

  /// La liaison avec ce pair est-elle dégradée ? L'écran affiche alors
  /// « Connexion faible », comme WhatsApp.
  final ValueNotifier<bool> connexionFaible = ValueNotifier(false);

  /// Le pair a-t-il coupé sa caméra (bouton, ou application en arrière-plan) ?
  /// L'écran affiche alors son avatar au lieu d'une image figée.
  bool cameraDistanteActive = true;

  Timer? _repriseTimer;
  int _tentativesReprise = 0;
  bool _enReprise = false;
  bool _offreRepriseEnVol = false;
  DateTime? _repriseDepuis;

  RTCPeerConnection? _pc;
  MediaStream? _remote;
  bool _started = false;

  /// Vrai seulement quand la session peut RÉELLEMENT traiter un signal :
  /// `_pc` créé ET pistes locales ajoutées.
  ///
  /// À ne pas confondre avec `_started`, qui marque l'entrée dans `start()`.
  /// Entre les deux il y a plusieurs `await` (création de la connexion,
  /// résolution des serveurs ICE, ajout des pistes) pendant lesquels des
  /// signaux arrivent : le WebSocket appelle `handleSignal` sans l'attendre,
  /// et le mesh publie la session dans `_peers` AVANT d'appeler `start()`.
  /// Se fier à `_started` faisait passer ces signaux dans `_applySignal` avec
  /// `_pc` encore nul : l'offre était jetée en silence, aucune answer n'était
  /// produite, et l'appel restait « Connexion en cours… » jusqu'à l'échec.
  bool _ready = false;
  bool _remoteReady = false;
  final _pendingSignals = <Map<String, dynamic>>[];
  final _iceQueue = <RTCIceCandidate>[];

  MediaStream? get remoteStream => _remote;
  bool get mediaConnected => _remote != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final raw = iceServers.isNotEmpty ? iceServers : WebrtcPeerSession.fallbackIce;
    final servers = normalizeIceServers(raw);
    // Configuration WebRTC :
    //  - iceTransportPolicy: "all"  → essaie d'abord P2P direct, puis relay TURN
    //  - bundlePolicy: "max-bundle" → 1 seul port UDP pour tous les médias
    //                                  (obligatoire pour beaucoup de firewalls)
    //  - rtcpMuxPolicy: "require"   → RTP + RTCP sur le même port
    //  - sdpSemantics: "unified-plan" → format SDP moderne (requis flutter_webrtc récent)
    _pc = await createPeerConnection({
      "iceServers": servers,
      "iceTransportPolicy": "all",
      "bundlePolicy": "max-bundle",
      "rtcpMuxPolicy": "require",
      "sdpSemantics": "unified-plan",
      // Quelques candidats collectés d'avance : la négociation (et chaque
      // reprise) démarre plus vite (guide du 31/10/2026).
      "iceCandidatePoolSize": 2,
    });
    _pc!.onIceCandidate = (RTCIceCandidate? c) {
      if (c == null) return;
      final preview = c.candidate ?? "";
      debugPrint("[webrtc/$peerId] ICE candidate: ${preview.length > 80 ? preview.substring(0, 80) : preview}");
      onSendSignal({"kind": "ice", "candidate": c.toMap()});
    };
    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint("[webrtc/$peerId] ICE state: $state");
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          // Peut se rétablir seul : on laisse un court sursis avant de payer
          // une négociation. Trois secondes, et non plus six : au-delà, une
          // coupure réelle a déjà coûté la moitié du plafond du serveur.
          _graceTimer?.cancel();
          _graceTimer = Timer(const Duration(seconds: 3), () {
            traceAppel("$peerId : toujours disconnected → reprise");
            _demarreLaReprise();
          });
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          // `failed` ne revient jamais tout seul : on tente sans attendre.
          _graceTimer?.cancel();
          traceAppel("$peerId : ICE failed → reprise immédiate");
          _demarreLaReprise(immediat: true);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _graceTimer?.cancel();
          _finDeReprise();
          unawaited(_reglerEmission());
          _demarrerMesure();
          break;
        default:
          break;
      }
    };
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint("[webrtc/$peerId] Connection state: $state");
    };
    _pc!.onTrack = (RTCTrackEvent e) {
      debugPrint("[webrtc/$peerId] ⬇️ onTrack: kind=${e.track.kind} streams=${e.streams.length}");
      if (e.streams.isNotEmpty) {
        _remote = e.streams.first;
        onUpdated();
      }
    };

    for (final track in localStream.getTracks()) {
      await _pc!.addTrack(track, localStream);
    }
    // Avant toute offre ou réponse : l'ordre des codecs s'écrit dans le SDP.
    await _preferH264();

    if (isOfferer) {
      await _createOffer();
    }

    // La session n'est déclarée prête qu'ici : les pistes locales sont posées,
    // donc l'answer produite en réponse à une offre en attente portera bien le
    // média. Ouvrir plus tôt renverrait une answer sans piste.
    _ready = true;
    await _flushPendingSignals();
  }

  // Serveurs ICE (STUN + TURN) pour la traversée NAT.
  //
  // STRUCTURE IMPORTANTE : chaque entrée doit avoir UN SEUL "urls" avec UN SEUL
  // protocole. Mélanger stun: et turn: dans un même objet ICEServer avec
  // username/credential est mal supporté par plusieurs implémentations WebRTC
  // (les credentials seraient appliquées au stun: aussi, ce qui trouble le stack).
  //
  // On propose plusieurs transports pour maximiser les chances de succès sur
  // réseaux mobiles restrictifs (4G Cameroun, WiFi d'entreprise, etc.) :
  //   1. STUN UDP alanya  : le plus rapide, résout la plupart des NATs
  //   2. STUN Google      : backup public au cas où alanya.cloud momentanément KO
  //   3. TURN UDP         : relay si STUN insuffisant (NAT symétrique)
  //   4. TURN TCP         : fallback si UDP entièrement bloqué
  //   5. TURNS 443        : dernier recours, passe même derrière les proxies HTTPS
  // Fallback utilisé UNIQUEMENT si /api/calls/ice échoue. Domaines corrigés
  // (les anciens "alanya2.cloud" / "google2.com" n'existaient pas → ENOTFOUND).
  // NB : les identifiants TURN statiques ci-dessous ne fonctionnent que si le
  // Coturn accepte aussi une auth statique ; sinon seuls les STUN servent de
  // secours. Le vrai chemin TURN passe par /api/calls/ice (HMAC).
  /// Secours STUN UNIQUEMENT, sur les domaines réellement en service.
  ///
  /// Les entrées TURN qui figuraient ici visaient `open.alanya.cloud` avec un
  /// identifiant statique : ce serveur répond `401 Unauthorized`, vérification
  /// faite. Elles ne fournissaient donc aucun relais — juste des candidats que
  /// la négociation essayait en vain avant d'abandonner.
  ///
  /// Il ne peut pas en aller autrement : les identifiants TURN sont des HMAC
  /// temporaires, ils ne peuvent venir que de `/api/calls/ice`. Un secours codé
  /// en dur ne sait donc offrir que du STUN — l'appel reste possible en direct,
  /// pas derrière un NAT symétrique. C'est le choix qu'a fait le modèle, et il
  /// vaut mieux qu'un relais qui prétend exister.
  static const fallbackIce = [
    {"urls": "stun:alanya226.com:3478"},
    {"urls": "stun:kemita.eu:3478"},
    {"urls": "stun:stun.l.google.com:19302"},
  ];
  /// Normalise la liste ICE avant de la passer à WebRTC :
  ///  - éclate un objet à `urls` multiples en une entrée par URL,
  ///  - ne met les identifiants que sur TURN/TURNS (jamais sur STUN).
  /// Corrige le format « bundlé » renvoyé par certaines sources (dont l'ancien
  /// /api/calls/ice) qui casse le TURN sur flutter_webrtc.
  static List<Map<String, dynamic>> normalizeIceServers(
    List<Map<String, dynamic>> input,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final s in input) {
      final urlsRaw = s["urls"];
      final username = s["username"];
      final credential = s["credential"];
      final urls = urlsRaw is List ? urlsRaw : [urlsRaw];
      for (final u in urls) {
        if (u == null) continue;
        final url = u.toString();
        final isStun = url.startsWith("stun:");
        final entry = <String, dynamic>{"urls": url};
        if (!isStun && username != null) entry["username"] = username;
        if (!isStun && credential != null) entry["credential"] = credential;
        out.add(entry);
      }
    }
    return out;
  }

  /// Ouvre la procédure de reprise, et prévient une seule fois.
  ///
  /// [immediat] saute l'attente du premier essai : sur `failed`, patienter ne
  /// sert à rien puisque l'état ne se répare pas de lui-même.
  ///
  /// [annoncer] : faux pour une reprise de précaution (réseau changé, demande
  /// du pair) — l'écran ne dit « Reconnexion… » que si notre liaison a
  /// réellement vacillé.
  void _demarreLaReprise({bool immediat = false, bool annoncer = true}) {
    if (_pc == null) return;
    if (!_enReprise) {
      _enReprise = true;
      _tentativesReprise = 0;
      _repriseDepuis = DateTime.now();
    }
    if (annoncer && !_repriseAnnoncee) {
      _repriseAnnoncee = true;
      onReconnecting?.call();
    }
    _planifieUnEssai(immediat: immediat);
  }

  /// La connexion temps réel vient de revenir pendant l'appel : le réseau a
  /// très probablement changé (Wi-Fi ↔ 4G). WebRTC peut mettre 10 à 30 s à
  /// s'apercevoir que l'ancien chemin est mort — l'image reste figée pendant
  /// ce temps. On relance donc la liaison TOUT DE SUITE, sans rien afficher :
  /// si elle allait bien, la reprise se conclut en deux secondes.
  void relancerApresChangementDeReseau() {
    if (_pc == null || !_ready) return;
    traceAppel("$peerId : réseau revenu → reprise de précaution");
    if (isOfferer) {
      _demarreLaReprise(immediat: true, annoncer: false);
    } else {
      onSendSignal({"kind": "ice_restart_request"});
    }
  }

  void _planifieUnEssai({bool immediat = false}) {
    _repriseTimer?.cancel();
    final depuis = _repriseDepuis;
    if (depuis != null && DateTime.now().difference(depuis) >= _plafondReprise) {
      traceAppel("$peerId : plafond de reprise atteint → connexion perdue");
      _abandonneLaReprise();
      return;
    }
    if (_tentativesReprise >= _essaisReprise.length) {
      traceAppel("$peerId : ${_essaisReprise.length} reprises sans succès → connexion perdue");
      _abandonneLaReprise();
      return;
    }
    final attente = immediat ? Duration.zero : _essaisReprise[_tentativesReprise];
    _tentativesReprise++;
    _repriseTimer = Timer(attente, _tenteUneReprise);
  }

  Future<void> _tenteUneReprise() async {
    final pc = _pc;
    if (pc == null || !_enReprise) return;

    // Celui qui n'offre pas ne relance pas : il le DEMANDE. Deux offres
    // croisées échouent toutes les deux.
    if (!isOfferer) {
      traceAppel("$peerId : demande de reprise envoyée à l'offreur");
      onSendSignal({"kind": "ice_restart_request"});
      _planifieUnEssai();
      return;
    }

    // Une offre part déjà, ou la connexion n'est pas au repos : relancer
    // maintenant lèverait `InvalidStateError` et casserait la session au lieu
    // de la réparer.
    // Une offre partie il y a longtemps, sans réponse (perdue avec le réseau) :
    // on la retire pour pouvoir en envoyer une neuve.
    final envoyee = _offreEnvoyeeLe;
    if (_offreRepriseEnVol &&
        envoyee != null &&
        DateTime.now().difference(envoyee) > _offreSansReponseMax &&
        pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      try {
        await pc.setLocalDescription(RTCSessionDescription("", "rollback"));
        _offreRepriseEnVol = false;
        traceAppel("$peerId : offre de reprise sans réponse → retirée");
      } catch (e) {
        traceAppel("$peerId : retrait de l'offre impossible — $e");
      }
    }

    if (_offreRepriseEnVol ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      traceAppel("$peerId : reprise différée (négociation en cours)");
      _planifieUnEssai();
      return;
    }

    try {
      _offreRepriseEnVol = true;
      /*
       * 🔴 `restartIce()` D'ABORD, LA CONTRAINTE ENSUITE — les deux, et pas un
       * seul des deux.
       *
       * `"IceRestart": true` est l'ancienne forme, passée dans les contraintes
       * héritées. Elle est censée être honorée, mais elle traverse une couche
       * de traduction jusqu'au natif, et rien dans l'API ne dit si elle a été
       * comprise : une offre part dans tous les cas, simplement sans nouvel
       * `ice-ufrag`, donc sans reprise réelle. C'est un échec parfaitement
       * silencieux.
       *
       * `restartIce()` est la forme moderne, présente dans la version du paquet
       * utilisée ici, et c'est CELLE QUE LE WEB EMPLOIE — où la reprise est
       * vérifiée. Les deux demandent la même chose ; les poser ensemble ne
       * coûte rien et supprime la question.
       */
      await pc.restartIce();
      final offre = await pc.createOffer({
        "mandatory": {
          "OfferToReceiveAudio": true,
          "OfferToReceiveVideo": isVideo,
          // De nouveaux `ice-ufrag`/`ice-pwd`, donc une collecte de candidats
          // neuve, sur des pistes déjà négociées.
          "IceRestart": true,
        },
        "optional": [],
      });
      await pc.setLocalDescription(offre);
      _offreEnvoyeeLe = DateTime.now();
      traceAppel("$peerId : OFFRE DE REPRISE envoyée (essai $_tentativesReprise)");
      onSendSignal({"kind": "offer", "sdp": offre.sdp, "type": offre.type});
    } catch (e) {
      _offreRepriseEnVol = false;
      traceAppel("$peerId : reprise impossible — $e");
    }
    _planifieUnEssai();
  }

  /// Le média est revenu : on efface tout et on le dit.
  void _finDeReprise() {
    _repriseTimer?.cancel();
    _repriseTimer = null;
    _offreRepriseEnVol = false;
    if (!_enReprise) return;
    _enReprise = false;
    _tentativesReprise = 0;
    _repriseDepuis = null;
    traceAppel("$peerId : connexion rétablie");
    if (_repriseAnnoncee) {
      _repriseAnnoncee = false;
      onReconnected?.call();
    }
  }

  void _abandonneLaReprise() {
    _repriseTimer?.cancel();
    _repriseTimer = null;
    _enReprise = false;
    _repriseAnnoncee = false;
    _offreRepriseEnVol = false;
    _repriseDepuis = null;
    onConnectionLost?.call();
  }

  /// Le réglage de l'émission (voir [_debitVideoMax]). Une fois par session :
  /// les paramètres survivent aux reprises, qui ne touchent pas aux pistes.
  Future<void> _reglerEmission() async {
    final pc = _pc;
    if (pc == null || _emissionReglee) return;
    _emissionReglee = true;
    try {
      for (final emetteur in await pc.getSenders()) {
        final nature = emetteur.track?.kind;
        if (nature == null) continue;
        final parametres = emetteur.parameters;
        // Sans encodage déclaré, on en pose un : sinon aucun réglage ne prend.
        if (parametres.encodings == null || parametres.encodings!.isEmpty) {
          parametres.encodings = [RTCRtpEncoding()];
        }
        for (final e in parametres.encodings!) {
          if (nature == "audio") {
            e.priority = RTCPriorityType.high;
            e.networkPriority = RTCPriorityType.high;
          } else {
            e.maxBitrate = _debitVideoMax;
            e.minBitrate = _debitVideoMin;
            e.maxFramerate = _cadenceVideoMax;
            e.priority = RTCPriorityType.low;
            e.networkPriority = RTCPriorityType.low;
          }
        }
        if (nature == "video") {
          parametres.degradationPreference = RTCDegradationPreference.BALANCED;
        }
        await emetteur.setParameters(parametres);
      }
      traceAppel("$peerId : émission réglée (son prioritaire, vidéo plafonnée)");
    } catch (e) {
      // Un appareil qui refuse un réglage garde le comportement par défaut :
      // l'appel n'en dépend pas.
      _emissionReglee = false;
      traceAppel("$peerId : réglage de l'émission impossible — $e");
    }
  }

  /// H.264 en tête (guide du 31/10/2026) : souvent accéléré par le matériel
  /// sur mobile, donc moins de charge et moins de saccades. Les autres codecs
  /// restent derrière, dans leur ordre : un appareil sans H.264 (ou un pair qui
  /// ne le parle pas) retombe simplement sur VP8.
  Future<void> _preferH264() async {
    final pc = _pc;
    if (pc == null || !isVideo) return;
    try {
      final codecs = (await getRtpSenderCapabilities('video')).codecs ?? [];
      bool h264(RTCRtpCodecCapability c) =>
          c.mimeType.toLowerCase() == 'video/h264';
      if (!codecs.any(h264)) return;
      final ordonnes = [...codecs.where(h264), ...codecs.where((c) => !h264(c))];
      for (final t in await pc.getTransceivers()) {
        if (t.sender.track?.kind == 'video') {
          await t.setCodecPreferences(ordonnes);
        }
      }
    } catch (e) {
      traceAppel("$peerId : préférence H.264 impossible — $e");
    }
  }

  void _demarrerMesure() {
    _mesure ??= Timer.periodic(const Duration(seconds: 3), (_) => _mesurer());
  }

  static double? _nombre(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  Future<void> _mesurer() async {
    final pc = _pc;
    if (pc == null || _enReprise) return;
    final List<StatsReport> rapports;
    try {
      rapports = await pc.getStats();
    } catch (_) {
      return;
    }
    var perteEmise = 0.0;
    var allerRetour = 0.0;
    double? debitDisponible;
    var recus = 0;
    var perdus = 0;
    for (final r in rapports) {
      final v = r.values;
      switch (r.type) {
        // Ce que le PAIR dit recevoir de nous.
        case 'remote-inbound-rtp':
          perteEmise = math.max(perteEmise, _nombre(v['fractionLost']) ?? 0);
          allerRetour = math.max(allerRetour, _nombre(v['roundTripTime']) ?? 0);
          break;
        case 'candidate-pair':
          final retenue = v['nominated'] == true || v['nominated'] == 'true';
          if (v['state'] == 'succeeded' && retenue) {
            allerRetour =
                math.max(allerRetour, _nombre(v['currentRoundTripTime']) ?? 0);
            debitDisponible =
                _nombre(v['availableOutgoingBitrate']) ?? debitDisponible;
          }
          break;
        // Ce que NOUS recevons du pair.
        case 'inbound-rtp':
          recus += (_nombre(v['packetsReceived']) ?? 0).toInt();
          perdus += (_nombre(v['packetsLost']) ?? 0).toInt();
          break;
      }
    }
    final dRecus = recus - _recusAvant;
    final dPerdus = perdus - _perdusAvant;
    _recusAvant = recus;
    _perdusAvant = perdus;
    final perteRecue =
        dRecus + dPerdus > 20 ? dPerdus / (dRecus + dPerdus) : 0.0;

    final degrade = perteEmise > _perteMax ||
        perteRecue > _perteMax ||
        allerRetour > _allerRetourMax ||
        (debitDisponible != null && debitDisponible < _debitDisponibleMin);
    if (degrade) {
      _bonnesDeSuite = 0;
      _mauvaisesDeSuite++;
      if (_mauvaisesDeSuite >= 2 && !connexionFaible.value) {
        traceAppel("$peerId : réseau dégradé (perte émise "
            "${(perteEmise * 100).round()} %, reçue ${(perteRecue * 100).round()} %, "
            "aller-retour ${(allerRetour * 1000).round()} ms) → vidéo allégée");
        connexionFaible.value = true;
        onUpdated();
        unawaited(_appliquerDebit(faible: true));
      }
    } else {
      _mauvaisesDeSuite = 0;
      _bonnesDeSuite++;
      if (_bonnesDeSuite >= 3 && connexionFaible.value) {
        traceAppel("$peerId : réseau rétabli → vidéo normale");
        connexionFaible.value = false;
        onUpdated();
        unawaited(_appliquerDebit(faible: false));
      }
    }
  }

  /// Vidéo allégée (moitié de définition, 300 kbit/s) ou normale.
  Future<void> _appliquerDebit({required bool faible}) async {
    final pc = _pc;
    if (pc == null || !isVideo) return;
    try {
      for (final emetteur in await pc.getSenders()) {
        if (emetteur.track?.kind != 'video') continue;
        final parametres = emetteur.parameters;
        final encodages = parametres.encodings;
        if (encodages == null || encodages.isEmpty) continue;
        for (final e in encodages) {
          e.maxBitrate = faible ? _debitVideoFaible : _debitVideoMax;
          e.scaleResolutionDownBy = faible ? 2.0 : 1.0;
        }
        await emetteur.setParameters(parametres);
      }
    } catch (e) {
      traceAppel("$peerId : adaptation du débit impossible — $e");
    }
  }

  /// Prévient le pair que notre caméra est coupée ou rallumée.
  void envoyerEtatCamera(bool active) {
    if (_pc == null) return;
    onSendSignal({"kind": "camera_state", "enabled": active});
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (!_ready) {
      _pendingSignals.add(signal);
      return;
    }
    await _applySignal(signal);
  }

  Future<void> _createOffer() async {
    final pc = _pc;
    if (pc == null) return;
    final offer = await pc.createOffer({
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": isVideo,
      },
      "optional": [],
    });
    await pc.setLocalDescription(offer);
    traceAppel("OFFRE creee et envoyee vers $peerId");
    onSendSignal({"kind": "offer", "sdp": offer.sdp, "type": offer.type});
  }

  Future<void> _applySignal(Map<String, dynamic> signal) async {
    final pc = _pc;
    // Ceinture et bretelles : plus aucun signal ne doit être perdu en silence.
    // S'il arrive alors que la connexion n'existe pas (ou plus), il retourne
    // dans la file — `_flushPendingSignals` le rejouera quand elle sera prête.
    if (pc == null) {
      _pendingSignals.add(signal);
      return;
    }
    final kind = signal["kind"] as String?;

    if (kind == "offer") {
      final sdp = signal["sdp"] as String?;
      if (sdp == null) return;
      final type = signal["type"] as String? ?? "offer";
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteReady = true;
      await _flushIceQueue();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      traceAppel("OFFRE recue de $peerId → ANSWER renvoyee");
      onSendSignal({"kind": "answer", "sdp": answer.sdp, "type": answer.type});
    } else if (kind == "answer") {
      final sdp = signal["sdp"] as String?;
      if (sdp == null) return;
      final type = signal["type"] as String? ?? "answer";
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteReady = true;
      // La réponse à notre offre de reprise est arrivée : la voie est libre
      // pour un éventuel essai suivant. Ce n'est PAS encore un succès — seul
      // `RTCIceConnectionStateConnected` le dira.
      _offreRepriseEnVol = false;
      _offreEnvoyeeLe = null;
      traceAppel("ANSWER recue de $peerId → negociation complete");
      await _flushIceQueue();
      /*
       * ⚠️ UNE REPRISE SUR UNE LIAISON QUI ALLAIT BIEN n'émet pas toujours de
       * nouvel état ICE : elle reste « connected », et sans ce contrôle la
       * reprise ne se concluait jamais — les essais s'épuisaient, et l'appel
       * était déclaré PERDU alors que le média passait.
       */
      if (_enReprise) {
        Timer(const Duration(seconds: 2), () {
          final etat = _pc?.iceConnectionState;
          if (etat == RTCIceConnectionState.RTCIceConnectionStateConnected ||
              etat == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
            _finDeReprise();
          }
        });
      }
    } else if (kind == "ice_restart_request") {
      // Le pair ne peut pas relancer lui-même — il n'est pas offreur. On le
      // fait pour lui, même si de notre côté l'état ICE n'a rien signalé :
      // une coupure n'est pas toujours vue des deux bouts en même temps.
      if (isOfferer) {
        traceAppel("$peerId : demande de reprise reçue");
        _demarreLaReprise(immediat: true, annoncer: false);
      }
    } else if (kind == "camera_state") {
      // Caméra du pair coupée ou rallumée (31/10/2026) : l'écran montre son
      // avatar plutôt qu'une image figée.
      cameraDistanteActive = signal["enabled"] != false;
      onUpdated();
    } else if (kind == "ice") {
      final raw = signal["candidate"];
      if (raw is! Map) return;
      final cand = RTCIceCandidate(
        raw["candidate"] as String?,
        raw["sdpMid"] as String?,
        raw["sdpMLineIndex"] as int?,
      );
      if (_remoteReady) {
        await pc.addCandidate(cand);
      } else {
        _iceQueue.add(cand);
      }
    }
  }

  Future<void> _flushPendingSignals() async {
    final copy = List<Map<String, dynamic>>.from(_pendingSignals);
    _pendingSignals.clear();
    for (final s in copy) {
      await _applySignal(s);
    }
  }

  Future<void> _flushIceQueue() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in List<RTCIceCandidate>.from(_iceQueue)) {
      await pc.addCandidate(c);
    }
    _iceQueue.clear();
  }

  Future<void> close() async {
    _mesure?.cancel();
    _mesure = null;
    connexionFaible.value = false;
    _graceTimer?.cancel();
    _graceTimer = null;
    _repriseTimer?.cancel();
    _repriseTimer = null;
    _enReprise = false;
    _repriseAnnoncee = false;
    _offreRepriseEnVol = false;
    _offreEnvoyeeLe = null;
    _emissionReglee = false;
    _repriseDepuis = null;
    _remote = null;
    await _pc?.close();
    _pc = null;
    _started = false;
    _ready = false;
    _remoteReady = false;
    _pendingSignals.clear();
    _iceQueue.clear();
  }
}
