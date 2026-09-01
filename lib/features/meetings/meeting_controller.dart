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

  /// Coupures que l'organisateur m'impose, à annoncer à l'écran.
  ///
  /// Un flux et non un état, pour la même raison que [alertes] : c'est un
  /// ÉVÉNEMENT ponctuel — « on vient de vous couper » — et non quelque chose à
  /// afficher en permanence. L'état durable qui en découle, lui, est déjà porté
  /// par [isMuted] et [isCameraOff], que la coupure a posés.
  Stream<MeetingCoupure> get coupures => _coupures.stream;
  final StreamController<MeetingCoupure> _coupures =
      StreamController<MeetingCoupure>.broadcast();

  /// Refus d'entrée prononcé par le serveur : salle pleine, réunion terminée,
  /// invitation absente.
  ///
  /// Un flux, pour la même raison que [alertes] et [coupures] : c'est un
  /// événement ponctuel. Ce qu'il laisse derrière lui n'est pas un état à
  /// afficher mais une salle DÉMONTÉE — le contrôleur a déjà tout refermé quand
  /// l'événement arrive.
  Stream<MeetingRefus> get refus => _refus.stream;

  /// J'AI ÉTÉ EXCLU de la réunion par l'organisateur.
  ///
  /// Un flux plutôt qu'un drapeau : la salle est démontée dans la foulée, et un
  /// drapeau posé sur un contrôleur qu'on vient de remettre à zéro se lit mal —
  /// il faudrait décider de quand l'effacer. L'événement, lui, se consomme une
  /// fois et ne laisse rien derrière.
  Stream<void> get exclusions => _exclusions.stream;
  final StreamController<void> _exclusions = StreamController<void>.broadcast();
  final StreamController<MeetingRefus> _refus =
      StreamController<MeetingRefus>.broadcast();

  /// La COMPOSITION de la réunion vient de changer : quelqu'un a été ajouté,
  /// exclu, ou son rôle a changé — depuis une route REST, et non depuis la
  /// salle.
  ///
  /// Un flux et non un état, pour la même raison que [alertes] et [coupures] :
  /// c'est un ÉVÉNEMENT ponctuel. Ce qu'il laisse derrière lui — le répertoire
  /// et la liste des invités à jour — est posé par la relecture, et se lit dans
  /// [invitesAbsents] comme dans [participantNames].
  ///
  /// À QUOI IL SERT AUX ÉCRANS : la fiche de la réunion tient sa PROPRE copie du
  /// [Meeting], que le contrôleur ne peut pas mettre à jour à sa place. Elle
  /// écoute donc ce flux pour relire à son tour, au lieu de brancher un second
  /// chemin sur la socket — il n'y a qu'une porte pour les événements de salle,
  /// et c'est ce contrôleur.
  Stream<MeetingComposition> get compositions => _compositions.stream;
  final StreamController<MeetingComposition> _compositions =
      StreamController<MeetingComposition>.broadcast();

  /// Une inscription est partie vers le serveur et attend sa réponse.
  ///
  /// ⚠️ C'EST LE SEUL MOYEN DE LIRE JUSTE UNE TRAME `error`. Le serveur en émet
  /// pour des choses très différentes qui portent toutes le même `meetingId` :
  /// un refus d'entrée, mais aussi « seul l'organisateur peut prolonger » au
  /// beau milieu d'une séance qui se déroule très bien. Démonter la salle sur
  /// la seconde serait pire que de ne rien faire sur la première.
  ///
  /// Posé avant CHAQUE `meeting_join` — l'entrée comme la réinscription après
  /// une coupure réseau, où la place peut avoir été prise entre-temps — et
  /// retiré à la réception de `meeting_joined`.
  bool _inscriptionEnAttente = false;

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

  /// Les personnes INVITÉES à la réunion, telles que `GET /api/meetings/:id`
  /// les donne — moi excepté, et sans celles qui ont décliné.
  ///
  /// ⚠️ CE N'EST PAS [_connectedPeerIds], ET IL NE FAUT SURTOUT PAS LES
  /// CONFONDRE. Cette liste vient de la BASE et dit qui est attendu ; l'autre
  /// vient de la SOCKET et dit qui est là. Un invité ajouté en cours de séance
  /// entre ici tout de suite et dans l'autre seulement s'il franchit la porte.
  final List<MeetingInvite> _invites = [];

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

  /// Mains levées des pairs, telles que le SERVEUR les relaie (`meeting_hand`).
  ///
  /// Rien n'est conservé côté serveur : qui arrive en cours de route ne voit
  /// pas les mains déjà levées. C'est aussi ce que fait le web — le geste est
  /// bref par nature, et une main levée finit par se baisser.
  final Set<String> _raisedHands = {};

  /// Mon propre état de main levée, posé lui aussi par la réponse du serveur et
  /// non par le clic : tout le monde voit la même main au même instant.
  bool myHandRaised = false;

  /// Qui présente son écran, dans l'ordre où les annonces sont arrivées.
  ///
  /// La vedette revient au DERNIER encore actif — même règle que le web, sans
  /// quoi les deux plateformes mettraient des participants différents en grand.
  /// Le serveur accepte délibérément DEUX présentateurs à la fois et relaie les
  /// deux : ne retenir qu'un nom ferait disparaître la vedette dès que le
  /// second s'arrête, alors que le premier présente toujours — son écran
  /// retomberait en vignette, recadrée au format visage.
  final List<String> _presentateurs = [];

  /// Le participant dont la piste vidéo est un ÉCRAN et doit passer en grand,
  /// ou nul si personne ne présente.
  ///
  /// Seul `meeting_screen` porte cette information : rien dans WebRTC ne
  /// distingue une piste d'écran d'une piste de caméra, les deux empruntant le
  /// même tuyau.
  String? get presentateurId =>
      _presentateurs.isEmpty ? null : _presentateurs.last;

  /// Le pair [peerId] partage-t-il son écran ?
  ///
  /// Vrai pour les DEUX présentateurs quand il y en a deux, alors que
  /// [presentateurId] n'en désigne qu'un : le second présente bel et bien,
  /// même si ce n'est pas lui qui occupe le grand cadre.
  bool isSharingScreen(String peerId) => _presentateurs.contains(peerId);

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

  /// Les invités qui ne sont PAS (encore) dans la salle.
  ///
  /// DÉRIVÉ À LA LECTURE, jamais stocké. La liste des invités vient de la base,
  /// la présence vient de la socket, et les deux bougent chacune de leur côté :
  /// un troisième champ tenu à la main finirait fatalement par contredire l'un
  /// des deux — il suffirait d'oublier de le mettre à jour dans un seul des
  /// quatre endroits qui retirent un pair.
  ///
  /// ⚠️ NE PAS L'AJOUTER À [participantCount]. Ce compteur-là dit combien de
  /// personnes sont DANS la salle, et l'en-tête l'affiche à côté du minuteur :
  /// y mêler des absents lui ferait annoncer du monde que personne ne voit ni
  /// n'entend.
  /// Les demandes d'invitation EN ATTENTE, telles que le serveur les rend à
  /// CETTE personne.
  ///
  /// 🔴 CE QUE CETTE LISTE CONTIENT DÉPEND DE QUI JE SUIS, et ce n'est pas
  /// décidé ici : l'organisateur reçoit toutes les demandes en attente, chacun
  /// des autres ne reçoit que celles qu'il a faites. Le filtre est dans la
  /// requête du serveur — refiltrer ici laisserait croire qu'on peut se fier à
  /// la liste pour savoir ce qui existe vraiment.
  ///
  /// ⚠️ NE PAS LA MÊLER À [invitesAbsents] NI À [participantCount]. Ces gens-là
  /// ne sont pas invités : ils sont PROPOSÉS, et l'organisateur n'a pas encore
  /// tranché. Les compter comme attendus ferait guetter quelqu'un qui pourrait
  /// bien ne jamais venir.
  List<MeetingInviteRequest> _demandes = const [];
  List<MeetingInviteRequest> get demandesEnAttente => _demandes;

  /// Relit les demandes en attente de la réunion active.
  ///
  /// Silencieux en cas d'échec : la salle reste utilisable sans cette liste, et
  /// une erreur de plus à l'écran pendant une réunion n'aide personne.
  Future<void> _relitLesDemandes(int meetingId) async {
    try {
      final d = await _meetings.fetchInviteRequests(meetingId);
      if (meetingId != activeMeetingId) return;
      _demandes = d.where((x) => x.estEnAttente).toList();
      notifyListeners();
    } catch (_) {
      // Sans droit ou sans réseau : on garde ce qu'on avait.
    }
  }

  List<MeetingInvite> get invitesAbsents => [
        for (final invite in _invites)
          if (!_connectedPeerIds.contains(invite.userId)) invite,
      ];

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
    // La place n'est PAS acquise pour autant : le serveur compte les sockets de
    // la salle, et la mienne vient de mourir. Quelqu'un a pu prendre la place
    // pendant la coupure — cette réinscription peut donc être refusée comme une
    // première entrée, et doit être lue comme telle.
    _inscriptionEnAttente = true;
    _rt.meetingJoin(id);
    // On n'annonce RIEN ici : ni l'état muet, ni la main levée.
    //
    // `meeting_join` traverse trois requêtes de base côté serveur AVANT que ma
    // socket ne soit inscrite dans la salle, alors que `meeting_hand` et les
    // signaux, eux, refusent immédiatement quiconque n'y figure pas encore.
    // Deux trames envoyées dos à dos sur la même boucle arrivaient donc pendant
    // que le join était encore suspendu, et étaient jetées sans la moindre
    // erreur — la réannonce ne réannonçait rien.
    //
    // Tout part de `_handleJoined`, à la RÉCEPTION de `meeting_joined`, c'est-à-
    // dire une fois le serveur prêt à m'écouter.
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
    // dans la salle et renvoie la liste des participants déjà présents — ou qui
    // REFUSE, la salle pouvant être pleine. Rien n'est acquis à cet instant :
    // seul `meeting_joined` fait de nous un participant.
    _inscriptionEnAttente = true;
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
    // ⚠️ LA MAIN LEVÉE N'EST PLUS ICI. Elle a son propre verbe serveur,
    // `meeting_hand`, que le web parle aussi. La laisser dans cette annonce
    // donnerait DEUX sources pour un même booléen — celle du serveur et
    // celle-ci, posée sur ma seule foi — qui finiraient par se contredire.
    final payload = {
      "kind": "meeting_state",
      "muted": isMuted,
      "cameraOff": isCameraOff,
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

  /// Lève ou baisse ma main.
  ///
  /// ⚠️ RIEN N'EST APPLIQUÉ LOCALEMENT : [myHandRaised] est posé à la réception
  /// de `meeting_hand`, que le serveur renvoie à l'auteur comme aux autres.
  /// L'allumer ici sur la seule foi du clic ferait diverger ma vignette de
  /// celle que les autres voient si la trame se perdait — et le web, lui,
  /// attend déjà la réponse du serveur.
  void toggleHandRaised() {
    final id = activeMeetingId;
    if (id == null) return;
    _rt.meetingHand(id, !myHandRaised);
  }

  /// Envoie un message dans le fil de la salle.
  ///
  /// ⚠️ RIEN N'EST AJOUTÉ LOCALEMENT, et c'est un changement de fond. Le
  /// serveur renvoie le message à son auteur comme aux autres, et c'est SON
  /// ordre qui fait foi : poser la bulle tout de suite la placerait ailleurs
  /// chez soi que chez les autres, dès que deux personnes écrivent en même
  /// temps. La bulle apparaît donc à la réception de [_handleMeetingMessage],
  /// avec `mine` déduit de l'expéditeur que le serveur a posé.
  void sendChatMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final id = activeMeetingId;
    if (id == null) return;
    _rt.meetingMessage(id, trimmed);
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

  /// Numéro de la dernière relecture demandée.
  ///
  /// Deux changements rapprochés lancent deux lectures, et RIEN NE GARANTIT
  /// QUE LA PREMIÈRE RÉPONDE EN PREMIER. Sans ce numéro, une réponse ancienne
  /// arrivée en dernier écraserait durablement la liste par un état périmé —
  /// exactement le défaut qu'on évitait en ne transportant pas la liste dans
  /// l'événement.
  int _relectureNo = 0;

  /// RELIT la réunion au serveur, et met à jour ce qui vient de la BASE.
  ///
  /// UNE SEULE SOURCE, `GET /api/meetings/:id` — la même pour le mobile, le web
  /// et la fiche de la réunion. Rien n'est déduit de l'événement qui a déclenché
  /// cette lecture : le serveur DIT que la composition a changé, il ne la
  /// transporte pas.
  ///
  /// 🔴 CE QUI EST TOUCHÉ, ET RIEN D'AUTRE : le répertoire des noms, celui des
  /// avatars, et la liste des invités. [_connectedPeerIds], le maillage WebRTC,
  /// les états muets, les mains levées et les présentateurs ne sont PAS
  /// reconstruits ici. Ils décrivent la SALLE, que seule la socket connaît ;
  /// cette lecture ne connaît que la liste des invités.
  ///
  /// ET C'EST CE QUI PROTÈGE L'IMAGE. La grille vidéo se construit sur
  /// `peerIds` et `remoteStreams` ; ses tuiles sont appariées PAR POSITION par
  /// Flutter, et un `RTCVideoRenderer` n'est détruit que si sa tuile disparaît
  /// de la liste. Écrire dans [_connectedPeerIds] à chaque relecture — même
  /// pour y remettre exactement les mêmes identifiants dans un autre ordre —
  /// ferait donc réinitialiser des renderers, et l'image de toute la salle
  /// clignoterait à chaque arrivée. Ici, la liste des présents ne bouge pas :
  /// seuls le nom et l'avatar affichés changent.
  ///
  /// Les noms déjà connus ne sont pas écrasés : `meeting_user_joined` porte le
  /// nom de celui qui entre, et il est au moins aussi frais que celui-ci.
  ///
  /// Échec silencieux : on se contentera du repli « Participant » jusqu'à la
  /// relecture suivante. Une réunion ne doit pas s'arrêter parce qu'une requête
  /// HTTP a échoué.
  Future<void> _relitLaComposition(int meetingId) async {
    final no = ++_relectureNo;
    try {
      final meeting = await _meetings.fetchMeeting(meetingId);
      // Une lecture plus récente est partie depuis, ou la salle a changé
      // pendant celle-ci : on ne pose rien.
      if (no != _relectureNo || meetingId != activeMeetingId) return;

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

      // Ceux qui ont DÉCLINÉ sont écartés : les annoncer comme attendus ferait
      // guetter quelqu'un qui a déjà dit non.
      final invites = <MeetingInvite>[
        for (final p in meeting.participants)
          if (p.userId != myUserId && p.status != MeetingInvite.statutDecline)
            MeetingInvite(
              userId: p.userId,
              nom: p.displayName,
              avatarUrl: p.avatarUrl,
            ),
      ];
      if (!_memeListeInvites(invites)) {
        _invites
          ..clear()
          ..addAll(invites);
        changed = true;
      }

      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('[MeetingController] relecture de la composition échouée: $e');
    }
  }

  /// La liste relue est-elle la même que celle qu'on affiche déjà ?
  ///
  /// Une relecture qui ne change rien ne doit RIEN notifier : le ticker
  /// redessine déjà la salle chaque seconde, y ajouter des reconstructions
  /// inutiles ferait travailler la grille vidéo pour rien.
  bool _memeListeInvites(List<MeetingInvite> autres) {
    if (_invites.length != autres.length) return false;
    for (var i = 0; i < _invites.length; i++) {
      final a = _invites[i];
      final b = autres[i];
      if (a.userId != b.userId ||
          a.nom != b.nom ||
          a.avatarUrl != b.avatarUrl) {
        return false;
      }
    }
    return true;
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
    // Même ménage que sur un départ annoncé : une main levée ou une
    // présentation laissées derrière un pair perdu resteraient à l'écran pour
    // quelqu'un qui n'est plus là.
    _raisedHands.remove(peerId);
    _presentateurs.remove(peerId);
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
      case "meeting_message":
        _handleMeetingMessage(e);
        break;
      case "meeting_hand":
        _handleMeetingHand(e);
        break;
      case "meeting_screen":
        _handleMeetingScreen(e);
        break;
      case "meeting_mute":
        _handleMeetingMute(e);
        break;
      // Le nom du verbe est celui que porte `VERBE_COMPOSITION` dans le backend
      // (`src/lib/salle-temps-reel.ts`) ; c'est la seule source à suivre s'il
      // change. Ce `switch` FILTRE, exactement comme la liste des types côté
      // web : un verbe absent d'ici n'atteint jamais son gestionnaire, et sans
      // la moindre erreur — c'est l'oubli qui a déjà coûté deux défauts sur
      // `meeting_screen` et `meeting_mute`.
      case "meeting_participants_changed":
        _handleCompositionChangee(e);
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
      case "error":
        _handleErreur(e);
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
      case "meeting_kicked":
        /*
         * 🔴 J'AI ÉTÉ EXCLU DE LA RÉUNION — et c'est à moi de raccrocher.
         *
         * ⚠️ LA TRAME EST DIFFUSÉE À TOUTE LA SALLE, pas au seul exclu : le
         * pont côté serveur relaie `{...donnees, type, meetingId}` à la salle
         * entière. Sans le test sur `toUserId`, TOUT LE MONDE quitterait la
         * réunion dès qu'une personne en est exclue.
         *
         * Le serveur retire aussi l'exclu de la salle de son côté, et annonce
         * son départ aux autres : cette branche-ci ne sert donc qu'à MON propre
         * écran. Sans elle, je resterais devant une grille de vignettes gelées,
         * micro ouvert, en croyant participer.
         */
        if (e["meetingId"] == activeMeetingId &&
            e["toUserId"] is String &&
            e["toUserId"] == myUserId) {
          _stopMesh();
          CallForegroundService.arreter();
          // Annoncé AVANT le démontage : `_clear()` notifie ses auditeurs, et
          // l'écran peut se refermer sur le champ avant d'avoir su pourquoi.
          if (!_exclusions.isClosed) _exclusions.add(null);
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

  /// Le serveur REFUSE quelque chose (`{ type: "error" }`).
  ///
  /// 🔴 CETTE TRAME ÉTAIT JETÉE, et c'est le bug que ce bloc referme. Le
  /// `switch` ci-dessus ne connaissait aucun `case "error"` : quand la salle
  /// était pleine, le serveur répondait un refus parfaitement clair, personne ne
  /// l'écoutait, et l'utilisateur restait seul dans une salle fantôme —
  /// caméra allumée, micro ouvert, service de premier plan démarré, minuteur qui
  /// tourne — sans le moindre message. Il ne pouvait que raccrocher lui-même,
  /// sans jamais savoir pourquoi personne n'arrivait.
  ///
  /// TROIS FILTRES, ET AUCUN N'EST FACULTATIF.
  ///
  ///   1. `meetingId` doit être le mien. Le serveur émet aussi des `error` pour
  ///      la messagerie (« Conversation interdite »), qui portent un `tempId` et
  ///      aucun `meetingId` : elles ne me concernent pas ici.
  ///
  ///   2. Il faut qu'une INSCRIPTION SOIT EN ATTENTE, sinon on démonterait la
  ///      salle sur « Seul l'organisateur peut prolonger la réunion » — un refus
  ///      qui arrive au beau milieu d'une séance qui se porte très bien.
  ///
  ///   3. Sauf pour `MEETING_FULL`, qui démonte dans tous les cas. Le serveur ne
  ///      l'émet que depuis l'entrée en salle : le recevoir signifie que ma
  ///      socket n'est PAS dans la salle, quel que soit ce que je croyais.
  ///
  /// Une erreur qui passe les filtres ferme tout AVANT de prévenir : on coupe
  /// d'abord la caméra et le micro, on explique ensuite. L'inverse laisserait
  /// filmer pendant qu'on lit.
  void _handleErreur(Map<String, dynamic> e) {
    final meetingId = (e["meetingId"] as num?)?.toInt();
    if (meetingId == null || meetingId != activeMeetingId) return;

    final code = e["code"] as String?;
    final pleine = code == MeetingRefus.codeSallePleine;
    if (!_inscriptionEnAttente && !pleine) {
      // Un refus en cours de séance, sur autre chose que l'entrée. On ne
      // démonte rien : le serveur a écarté UNE demande, pas ma participation.
      debugPrint('[MeetingController] refus serveur ignoré : ${e["message"]}');
      return;
    }

    final refus = MeetingRefus(
      code: code,
      // Repli sur une phrase à nous quand le serveur n'en donne pas : un
      // dialogue vide serait pire que le silence.
      messageServeur: (e["message"] as String?)?.trim().isNotEmpty == true
          ? e["message"] as String
          : "Le serveur a refusé l'entrée dans cette réunion.",
      plafond: (e["plafond"] as num?)?.toInt(),
      actuel: (e["actuel"] as num?)?.toInt(),
      // Le type de la RÉUNION, que seul le serveur connaît. `activeIsVideo` dit
      // comment MOI j'entrais — une réunion vidéo rejointe en audio après un
      // échec caméra vaut 2 ici et `false` là-bas.
      typeMedia: (e["typeMedia"] as num?)?.toInt(),
      // Capturé MAINTENANT, avant le démontage qui remet ce compteur à zéro.
      // C'est ce qui décide qui parle : la salle si elle est ouverte, le bandeau
      // global sinon — sans quoi un refus reçu salle réduite ne dirait rien à
      // personne, ou serait annoncé deux fois.
      salleAffichee: roomVisible,
    );

    _demonteSansPrevenirLeServeur();
    if (!_refus.isClosed) _refus.add(refus);
  }

  /// Referme tout ce que [join] avait monté, SANS envoyer `meeting_leave`.
  ///
  /// Pas de `meeting_leave` parce qu'on n'est jamais entré : le serveur nous a
  /// refusé la porte, sa salle ne nous contient pas. Lui annoncer un départ le
  /// ferait chercher un participant qui n'existe pas — et, dans le cas d'une
  /// réinscription refusée, diffuserait un `meeting_user_left` à toute la salle
  /// pour quelqu'un qu'elle a déjà oublié.
  void _demonteSansPrevenirLeServeur() {
    _stopMesh();
    CallForegroundService.arreter();
    // `_clear()` arrête le ticker et remet l'état à neuf, `isActive` compris :
    // le bandeau global disparaît de lui-même.
    _clear();
  }

  void _handleJoined(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId == null || meetingId != activeMeetingId) return;

    // La place est ACQUISE : les erreurs qui suivront ne parleront plus de mon
    // entrée, et ne doivent donc plus démonter la salle.
    _inscriptionEnAttente = false;

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
    // invisibles dans la grille et la fiche participants. La même lecture pose
    // la liste des invités, pour que la fiche sache dès l'entrée qui est encore
    // attendu.
    _relitLaComposition(meetingId);
    // Les demandes en attente au moment ou j entre : sans cette lecture, la
    // liste des membres n en montrerait aucune tant que rien ne bouge.
    _relitLesDemandes(meetingId);
    // Annonce mon état muet courant à ceux déjà présents.
    _broadcastState();
    // ET MA MAIN, si elle était levée. Le serveur ne conserve rien : la salle
    // que je viens d'intégrer ignore tout de ma demande de parole, alors que ma
    // propre vignette l'affiche encore. Sans cette réannonce après une coupure
    // réseau, mon écran montrerait une main que plus personne ne voit.
    if (myHandRaised) _rt.meetingHand(meetingId, true);
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
    // Le présentateur s'en va : le serveur annonce lui-même la fin de son
    // partage avant son départ, mais on referme aussi ici, au cas où la trame
    // se perdrait. Il faut le retirer de la LISTE et pas seulement de la
    // vedette : l'y laisser le ferait revenir en grand cadre — absent, et sur
    // son dernier cadre figé — dès que le présentateur SUIVANT s'arrêterait.
    _presentateurs.remove(userId);
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

    // Signal applicatif : état d'un participant (muet/caméra).
    //
    // ⚠️ CE CANAL RESTE ENTRE MOBILES. Le serveur ne l'inspecte pas — il ne
    // fait que relayer de pair à pair — et le web n'en émet ni n'en lit. L'état
    // muet d'un participant web reste donc inconnu ici : voir le compte rendu,
    // c'est une divergence à traiter à part, sur le serveur.
    //
    // La main levée n'y est plus : elle a son propre verbe serveur.
    if (kind == "meeting_state") {
      final muted = signal["muted"] == true;
      if (_peerMuted[fromUserId] != muted) {
        _peerMuted[fromUserId] = muted;
        notifyListeners();
      }
      return;
    }

    // Sinon : signal de négociation WebRTC.
    _mesh?.handleSignal(fromUserId, signal);
  }

  /// Message reçu dans le fil de la salle (`meeting_message`).
  ///
  /// C'est le verbe du serveur, celui que le web parle aussi. Le mobile
  /// écrivait auparavant dans un `meeting_signal` de pair à pair : le fil ne
  /// franchissait pas la frontière entre les deux plateformes.
  ///
  /// MON PROPRE MESSAGE REPASSE PAR ICI, le serveur le renvoyant à tout le
  /// monde y compris à son auteur. C'est la seule façon d'avoir le même fil
  /// dans le même ordre partout ; `mine` se déduit de l'expéditeur que le
  /// serveur a posé, jamais du client, qui pourrait écrire au nom d'un autre.
  void _handleMeetingMessage(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    final text = e["text"] as String?;
    if (fromUserId == null || text == null || text.trim().isEmpty) return;

    final mine = fromUserId == myUserId;
    // Le nom vient du serveur ; on ne retombe sur le répertoire local que s'il
    // manque, et sur « Moi » pour ses propres messages.
    final fromName = (e["displayName"] as String?)?.trim().isNotEmpty == true
        ? e["displayName"] as String
        : mine
            ? (myDisplayName ?? "Moi")
            : (_participantNames[fromUserId] ?? "Participant");
    // L'horodatage aussi est celui du serveur : deux téléphones mal réglés
    // rangeraient sinon le fil différemment.
    final sentAt =
        DateTime.tryParse(e["sentAt"] as String? ?? "")?.toLocal() ??
            DateTime.now();

    _chatMessages.add(MeetingChatMessage(
      fromUserId: fromUserId,
      fromName: fromName,
      text: text,
      sentAt: sentAt,
      mine: mine,
    ));
    // Ses propres messages ne se comptent pas comme non lus : on vient de les
    // écrire. Le panneau peut s'être refermé entre l'envoi et l'écho.
    if (!_chatOpen && !mine) _unreadChatCount++;
    notifyListeners();
  }

  /// Main levée ou baissée (`meeting_hand`), relayée par le serveur à toute la
  /// salle — l'auteur compris, d'où le traitement de mon propre identifiant.
  void _handleMeetingHand(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    if (fromUserId == null) return;
    final levee = e["levee"] == true;

    if (fromUserId == myUserId) {
      if (myHandRaised == levee) return;
      myHandRaised = levee;
      notifyListeners();
      return;
    }

    final avant = _raisedHands.contains(fromUserId);
    if (levee == avant) return;
    if (levee) {
      _raisedHands.add(fromUserId);
    } else {
      _raisedHands.remove(fromUserId);
    }
    notifyListeners();
  }

  /// L'organisateur a coupé le micro ou la caméra de quelqu'un
  /// (`meeting_mute`), et le serveur l'annonce à TOUTE la salle.
  ///
  /// DEUX LECTURES DE LA MÊME TRAME, selon qui est visé :
  ///  - c'est moi → j'obéis, en éteignant réellement la piste ;
  ///  - c'est un autre → je note son micro coupé, pour que ma grille l'affiche.
  ///
  /// Sans ce second cas, un micro s'éteindrait dans la salle sans que personne
  /// comprenne pourquoi — c'est précisément pour cela que le serveur diffuse à
  /// tout le monde et pas au seul destinataire.
  ///
  /// ⚠️ AUCUN CONTRÔLE D'AUTORISATION ICI : le serveur a déjà relu l'organisateur
  /// en base avant de relayer, et lui seul peut le faire honnêtement. Revérifier
  /// sur [organiserId] — que le client tient de sa propre initialisation —
  /// n'ajouterait aucune sécurité et refuserait à tort une coupure légitime si
  /// cet identifiant manquait (salle rouverte depuis le bandeau, par exemple).
  void _handleMeetingMute(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    final toUserId = e["toUserId"] as String?;
    final media = e["media"] as String?;
    // Le test de nullité est SÉPARÉ de celui des valeurs admises : comparer à
    // deux constantes ne suffit pas à promouvoir `media` en non-nullable aux
    // yeux de l'analyseur, et [MeetingCoupure] en attend un vrai.
    if (fromUserId == null || toUserId == null || media == null) return;
    if (media != "audio" && media != "video") return;

    if (toUserId != myUserId) {
      // Un AUTRE vient d'être coupé. Seul le micro a un état affiché ici — une
      // caméra coupée se voit d'elle-même, sa vignette retombant sur l'avatar.
      //
      // ⚠️ CET ÉTAT PEUT VIEILLIR POUR UN PARTICIPANT WEB. `_peerMuted` est
      // normalement tenu à jour par le signal `meeting_state`, que le web
      // n'émet pas : s'il se rallume aussitôt, ma vignette le montrera coupé à
      // tort. C'est l'envers de la divergence déjà notée dans [_handleSignal],
      // où l'état muet du web restait inconnu — afficher la coupure au moment
      // où elle a lieu vaut mieux que ne jamais rien montrer, et un mobile,
      // lui, se corrige de lui-même dès son prochain basculement.
      if (media == "audio" && _peerMuted[toUserId] != true) {
        _peerMuted[toUserId] = true;
        notifyListeners();
      }
      return;
    }

    // C'est MOI qu'on coupe. On emprunte exactement le chemin des boutons
    // [toggleMute] et [toggleCamera] : changer l'icône sans toucher à la piste
    // laisserait le micro ouvert derrière un cadenas dessiné.
    if (media == "audio") {
      if (isMuted) return;
      isMuted = true;
      _mesh?.localStream?.getAudioTracks().forEach((track) {
        track.enabled = false;
      });
      // Même annonce qu'après un appui sur « Muet » : les autres mobiles lisent
      // l'état muet dans ce signal, et non dans la coupure elle-même.
      _broadcastState();
    } else {
      // ⚠️ RIEN EN AUDIO SEUL, et c'est ce qui garantit qu'on peut se rallumer.
      // Le bouton caméra n'existe dans la salle que si [activeIsVideo] : couper
      // une caméra que je n'ai pas m'enfermerait dans un état sans interrupteur
      // pour en sortir — donc un verrou, précisément ce qu'on ne veut pas.
      if (!activeIsVideo) return;
      if (isCameraOff) return;
      isCameraOff = true;
      _mesh?.localStream?.getVideoTracks().forEach((track) {
        track.enabled = false;
      });
    }

    // On le DIT à celui qu'on coupe : un micro qui s'éteint tout seul passe
    // pour une panne. Le nom vient du répertoire de la salle, avec un repli sur
    // la fonction — l'organisateur peut ne pas être encore résolu.
    if (!_coupures.isClosed) {
      _coupures.add(MeetingCoupure(
        media: media,
        parNom: _participantNames[fromUserId],
      ));
    }
    notifyListeners();
  }

  /// Demande à [userId] de couper son micro (`"audio"`) ou sa caméra
  /// (`"video"`).
  ///
  /// COUPE, MAIS NE VERROUILLE PAS : l'autre peut se rallumer aussitôt, comme
  /// dans Zoom, Meet et Teams. Couper sert à faire taire un micro oublié, pas à
  /// bâillonner quelqu'un.
  ///
  /// Le test sur [jeSuisOrganisateur] n'est qu'un confort d'interface, à
  /// l'image de [prolonger] : c'est le SERVEUR qui tranche, en relisant
  /// l'organisateur en base, et il ignore la trame en silence s'il refuse.
  ///
  /// Rien n'est appliqué localement : ni la piste de l'autre, qu'on ne peut pas
  /// atteindre, ni son état muet affiché, qui arrive par l'écho du serveur.
  void couperParticipant(String userId, String media) {
    final id = activeMeetingId;
    if (id == null || !jeSuisOrganisateur) return;
    // Se couper soi-même par ce chemin n'aurait pas de sens : mes propres
    // boutons agissent sur mes pistes sans passer par le serveur.
    if (userId == myUserId) return;
    if (media != "audio" && media != "video") return;
    _rt.meetingMute(id, userId, media);
  }

  /// LA COMPOSITION DE LA RÉUNION A CHANGÉ (`meeting_participants_changed`).
  ///
  /// POURQUOI CE VERBE EXISTE. L'API et le serveur temps réel sont DEUX
  /// PROCESSUS. Une route REST qui ajoute quelqu'un écrit en base et n'a aucun
  /// accès aux sockets : elle ne pouvait prévenir que des APPAREILS, par
  /// notification poussée — donc les nouveaux invités, et eux seuls. Ceux qui
  /// étaient déjà dans la salle ne voyaient bouger ni le nombre de participants
  /// ni la liste des invités, et devaient sortir et revenir. Le serveur ouvre
  /// désormais un pont interne : la route prévient le serveur temps réel, qui
  /// diffuse ce verbe à toute la salle.
  ///
  /// IL NE PORTE PAS LA NOUVELLE LISTE, et c'est voulu. Il DIT qu'elle a
  /// changé, on la RELIT :
  ///
  ///  - une liste transportée ici aurait sa propre forme, à tenir d'accord pour
  ///    toujours avec celle de `GET /api/meetings/:id` — deux vérités pour une
  ///    seule réunion, et une fusion à écrire de ce côté comme du côté web ;
  ///  - un « ça a changé » est IDEMPOTENT : quel que soit l'ordre d'arrivée de
  ///    deux annonces rapprochées, la dernière relecture dit le vrai, alors que
  ///    la dernière liste arrivée n'est pas forcément la plus récente.
  ///
  /// UN SEUL VERBE POUR TOUS LES CAS, le motif étant DANS la trame. Un motif
  /// qu'on ne connaît pas encore — l'exclusion, le changement de rôle — relance
  /// quand même la relecture, là où un type inconnu serait tombé sans bruit
  /// dans le `switch`. Il n'y aura donc rien à ajouter ici le jour où le serveur
  /// en émettra un nouveau.
  ///
  /// L'ÉVÉNEMENT EST ÉMIS SANS ATTENDRE LA LECTURE, et c'est délibéré : les
  /// écrans qui tiennent leur propre copie de la réunion relisent la leur en
  /// parallèle, et n'ont aucune raison d'attendre la nôtre.
  void _handleCompositionChangee(Map<String, dynamic> e) {
    final meetingId = (e["meetingId"] as num?)?.toInt();
    if (meetingId == null) return;

    /*
     * 🔴 L'ANNONCE PASSE MÊME QUAND ON N'EST PAS DANS LA RÉUNION (26/08/2026).
     *
     * Ce filtre disait `meetingId != activeMeetingId`, et `activeMeetingId`
     * n'est posé qu'en ENTRANT dans une salle. L'organisateur qui consulte la
     * fiche de sa réunion sans y être entré n'a donc pas de réunion active :
     * l'annonce arrivait bien jusqu'ici — le serveur la lui adresse
     * personnellement depuis le 26/08 — et elle était jetée une ligne plus
     * loin. Il fallait toujours tirer pour rafraîchir, ce que le user a
     * signalé.
     *
     * LA RELECTURE INTERNE, ELLE, RESTE RÉSERVÉE À LA RÉUNION ACTIVE : elle
     * remplit `_participantNames`, `_connectedPeerIds` et compagnie, qui
     * décrivent LA SALLE OÙ L'ON EST. Les remplir avec une autre réunion
     * mettrait dans la grille des gens qu'on n'entend pas.
     */
    if (meetingId == activeMeetingId) {
      _relitLaComposition(meetingId);
      // Les motifs INVITE_* ne changent pas la composition mais la liste des
      // demandes. Relire les deux sur le meme verbe evite d en oublier un le
      // jour ou le serveur en ajoutera un troisieme.
      _relitLesDemandes(meetingId);
    }

    // Le flux, lui, part toujours : chaque écran tient sa propre copie et sait
    // seul si l'annonce le concerne — ils comparent déjà l'identifiant.
    if (_compositions.isClosed) return;
    _compositions.add(MeetingComposition(
      meetingId: meetingId,
      motif: e["motif"] as String?,
      parUserId: e["parUserId"] as String?,
      nombre: (e["nombre"] as num?)?.toInt(),
    ));
  }

  /// Qui présente son écran (`meeting_screen`).
  ///
  /// POURQUOI CE VERBE COMPTE. La piste vidéo d'un écran emprunte exactement le
  /// même tuyau que celle d'une caméra, et rien dans WebRTC ne dit ce qu'elle
  /// montre. Sans cette annonce, l'écran d'un participant web arriverait ici
  /// comme une vignette de visage : recadrée au format portrait, donc amputée
  /// de la barre d'outils ou de la dernière colonne du tableau qu'on partageait
  /// justement.
  ///
  /// Le mobile n'ÉMET pas de partage — flutter_webrtc ne l'offre pas
  /// simplement, et ce n'est pas demandé. Il ne fait que le recevoir.
  ///
  /// Le serveur rejoue ce message à qui entre au milieu d'une présentation : le
  /// nouveau venu sait donc lui aussi ce qu'il regarde.
  void _handleMeetingScreen(Map<String, dynamic> e) {
    final meetingId = e["meetingId"] as int?;
    if (meetingId != activeMeetingId) return;

    final fromUserId = e["fromUserId"] as String?;
    if (fromUserId == null) return;

    if (e["partage"] == true) {
      if (_presentateurs.contains(fromUserId)) return;
      _presentateurs.add(fromUserId);
    } else {
      if (!_presentateurs.remove(fromUserId)) return;
    }
    notifyListeners();
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
    // Sans cette remise à zéro, une erreur reçue longtemps après la réunion
    // suivante serait lue comme un refus d'entrée et démonterait une salle où
    // l'on est parfaitement installé.
    _inscriptionEnAttente = false;
    _roomScreensOpen = 0;
    _participantNames.clear();
    _participantAvatars.clear();
    _connectedPeerIds.clear();
    // Sans cela, la fiche de la réunion SUIVANTE annoncerait comme attendus les
    // invités de la précédente, avant même la première relecture.
    _invites.clear();
    // Sans ca, les demandes de la reunion precedente s afficheraient dans la
    // suivante, ou l organisateur n est peut-etre meme pas le meme.
    _demandes = const [];
    _peerMuted.clear();
    _raisedHands.clear();
    // Un reste de la réunion précédente mettrait un absent en grand dès
    // l'entrée dans la suivante.
    _presentateurs.clear();
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
    _coupures.close();
    _refus.close();
    _exclusions.close();
    _compositions.close();
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

/// Coupure imposée par l'organisateur : mon micro ou ma caméra vient d'être
/// éteint par quelqu'un d'autre que moi.
class MeetingCoupure {
  const MeetingCoupure({required this.media, this.parNom});

  /// `"audio"` (micro) ou `"video"` (caméra).
  final String media;

  /// Nom de l'organisateur, ou nul s'il n'est pas encore résolu dans la salle.
  final String? parNom;

  bool get estAudio => media == "audio";
}

/// Refus d'entrée en salle prononcé par le serveur.
///
/// ⚠️ LA SALLE EST DÉJÀ DÉMONTÉE quand cet objet arrive : caméra éteinte, micro
/// fermé, service de premier plan arrêté. Il ne reste à l'écran qu'à EXPLIQUER —
/// et à se refermer, puisqu'il n'y a plus de réunion derrière lui.
class MeetingRefus {
  const MeetingRefus({
    required this.code,
    required this.messageServeur,
    required this.salleAffichee,
    this.plafond,
    this.actuel,
    this.typeMedia,
  });

  /// Le code que le serveur pose sur un refus de plafond, sur la socket comme
  /// sur les routes HTTP. Les autres refus d'entrée n'en portent aucun.
  static const codeSallePleine = "MEETING_FULL";

  /// `MEETING_FULL`, ou nul pour un refus qui n'en porte pas (« Réunion
  /// introuvable », « Cette réunion est terminée », « Vous n'êtes pas invité »).
  final String? code;

  /// La phrase du serveur, toujours en français.
  ///
  /// ⚠️ ELLE NE SERT QUE DE REPLI. Un texte de serveur n'est jamais traduit,
  /// alors que cette application se veut multilingue : quand on sait refaire la
  /// phrase à partir des chiffres, on la refait. C'est d'ailleurs pour cela que
  /// le serveur envoie `plafond` et `actuel` en plus du message.
  final String messageServeur;

  /// L'écran de salle était-il affiché au moment du refus ?
  ///
  /// Départage les deux surfaces qui écoutent ce flux — la salle et le bandeau
  /// global — pour que le refus soit annoncé UNE fois, et jamais zéro.
  final bool salleAffichee;

  /// Nombre de places de la réunion, organisateur compris. Nul hors
  /// [estSallePleine].
  final int? plafond;

  /// Nombre de personnes présentes au moment du refus. Nul hors
  /// [estSallePleine].
  final int? actuel;

  /// Type de la réunion : 1 = audio, 2 = vidéo. Celui de la RÉUNION, pas le
  /// mien — une réunion vidéo rejointe en audio faute de caméra vaut 2.
  final int? typeMedia;

  bool get estSallePleine => code == codeSallePleine;

  bool get estVideo => typeMedia == 2;

  String get titre => estSallePleine ? "Réunion pleine" : "Entrée refusée";

  /// Ce qu'on montre à l'utilisateur.
  ///
  /// TROIS CHOSES, DANS CET ORDRE : combien de places, combien sont prises, et
  /// ce qui peut aider. Sans le dernier point, le message ne fait qu'annoncer un
  /// échec ; avec lui, il ouvre une porte — une réunion audio accueille plus de
  /// monde qu'une vidéo, parce qu'une image coûte bien plus cher qu'une voix sur
  /// un maillage où chacun émet vers tous les autres.
  ///
  /// La suggestion audio ne s'affiche QUE pour une réunion vidéo : la proposer
  /// dans une réunion déjà audio serait absurde, et ferait douter du reste du
  /// message.
  String get texte {
    // Sans les chiffres, on n'a rien de mieux à dire que le serveur : lui seul
    // connaît la raison de ce refus-là.
    if (!estSallePleine || plafond == null) return messageServeur;

    final media = estVideo ? "vidéo" : "audio";
    final prises = actuel == null
        ? "Toutes les places sont prises."
        : "$actuel ${actuel == 1 ? "personne y est déjà" : "personnes y sont déjà"} : il n'en reste aucune.";
    final suite = estVideo
        ? "Une réunion audio accueille plus de monde qu'une réunion vidéo — "
            "une image coûte environ dix fois plus cher qu'une voix. Demandez-en "
            "une à l'organisateur, ou réessayez dès qu'une place se libère."
        : "Réessayez dès qu'une place se libère.";
    return "Cette réunion $media est limitée à $plafond participants, "
        "organisateur compris. $prises\n\n$suite";
  }

  /// La même chose en une phrase, pour le bandeau global.
  ///
  /// Une version courte et non le [texte] tronqué : ce message-là s'affiche
  /// quand la salle était RÉDUITE, donc par-dessus autre chose et sans qu'on
  /// l'ait demandé. Il doit se lire d'un coup d'œil, dire que la réunion s'est
  /// arrêtée et pourquoi — le conseil sur l'audio, lui, n'a pas sa place dans un
  /// bandeau qui disparaît en quatre secondes.
  String get texteCourt {
    if (!estSallePleine || plafond == null) return messageServeur;
    return "Réunion quittée : elle est limitée à $plafond participants, "
        "et toutes les places sont prises.";
  }
}

/// La composition d'une réunion vient de changer, depuis une route REST.
///
/// ⚠️ NE PORTE PAS LA NOUVELLE LISTE — voir
/// [MeetingController._handleCompositionChangee] pour le pourquoi. Ce qu'il
/// porte ne sert qu'à FORMULER ce qui s'est passé ; ce qui sert à AFFICHER se
/// relit au serveur.
class MeetingComposition {
  const MeetingComposition({
    required this.meetingId,
    this.motif,
    this.parUserId,
    this.nombre,
  });

  /// Les motifs que le serveur émet aujourd'hui — voir `MotifSalle` dans
  /// `src/lib/salle-temps-reel.ts`, la seule source à suivre.
  static const motifAjout = "PARTICIPANTS_ADDED";
  static const motifRetrait = "PARTICIPANT_REMOVED";
  static const motifRole = "ROLE_CHANGED";

  final int meetingId;

  /// CE QUI a changé, en CODE et jamais en phrase : le serveur ne rend aucun
  /// texte affichable.
  ///
  /// ⚠️ VOLONTAIREMENT UNE CHAÎNE LIBRE, et non une énumération. Un motif
  /// inconnu de cette version de l'application ne doit RIEN empêcher : la
  /// relecture reste juste quoi qu'il arrive, et c'est elle qui compte. Une
  /// énumération obligerait à un repli « inconnu » que personne ne penserait à
  /// traiter.
  final String? motif;

  /// Qui a provoqué le changement. Déjà connu de toute la salle.
  final String? parUserId;

  /// Combien de lignes bougent. Un nombre, pas une liste : de quoi annoncer
  /// quelque chose tout de suite, rien à fusionner.
  final int? nombre;

  bool get estUnAjout => motif == motifAjout;
}

/// Quelqu'un d'INVITÉ à la réunion — déjà dans la salle ou pas encore.
///
/// Vient de `GET /api/meetings/:id`, donc de la base : à ne pas confondre avec
/// un pair de [MeetingController.peerIds], qui vient de la socket et qui est,
/// lui, réellement là.
class MeetingInvite {
  const MeetingInvite({
    required this.userId,
    required this.nom,
    this.avatarUrl,
  });

  /// Le statut d'un invité qui a DÉCLINÉ, tel que le serveur le pose.
  static const statutDecline = 2;

  final String userId;
  final String nom;
  final String? avatarUrl;
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
