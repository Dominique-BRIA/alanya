import 'dart:async';

// `widgets.dart` plutôt que `foundation.dart`, qu'il réexporte :
// `WidgetsBinding.lifecycleState` sert à distinguer l'application ouverte
// (bandeau interne) de l'application réduite ou fermée (écran d'appel natif).
import 'package:alanya_telecom/alanya_telecom.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import '../../core/call_permissions.dart';
import '../../core/debug_overlay.dart';
import '../../core/call_foreground_service.dart';
import '../../core/call_ui_native.dart';
import '../../core/lock_screen_call.dart';
import '../../core/proximite_appel.dart';
import '../../core/push_service.dart';
import '../../core/realtime_client.dart';
import '../../core/ringtone_service.dart';
import '../../models/call_record.dart';
import 'calls_repository.dart';
import 'webrtc_group_mesh.dart';
import 'webrtc_peer_session.dart';

enum ActiveCallRole { outgoing, incoming, ongoing }

/// Étape d'un appel passé à un standard (centre d'appels).
///
/// Il n'y en a que deux, et c'est voulu : dès que l'agent décroche, la session
/// disparaît et l'appel redevient un appel ordinaire. Un troisième état
/// « en communication » ferait doublon avec [ActiveCallRole].
enum IvrEtape { menu, attente }

/// Une touche du menu d'un standard.
///
/// [disponible] est calculé par le serveur : un service peut être ANNONCÉ par
/// l'invite vocale sans qu'aucun agent ne le desserve encore. On l'affiche
/// quand même — l'appelant vient de l'entendre, le masquer serait déroutant —
/// mais grisé, et l'appui dessus reçoit son propre message.
class IvrOption {
  const IvrOption({
    required this.digit,
    required this.label,
    required this.disponible,
    this.nomService,
  });

  final int digit;

  /// `center.libelle` — le nom interne de la ligne. Repli, jamais le premier
  /// choix pour l'affichage.
  final String label;
  final bool disponible;

  /// `center.nom_service` — le nom du service tel qu'il doit être MONTRÉ.
  ///
  /// ⚠️ Nul quand la colonne est vide, et le serveur ne renvoie jamais de chaîne
  /// vide : il normalise à `null` dès la lecture. Les deux règles d'affichage
  /// demandées en dépendent, et elles ne sont pas les mêmes — sur le pavé, on
  /// retombe sur [label] ; sous le nom du centre, on n'affiche RIEN.
  final String? nomService;

  /// Ce qu'on montre pour désigner cette touche sur le pavé.
  String get nomAffiche => nomService ?? label;

  static IvrOption? depuisJson(dynamic brut) {
    if (brut is! Map) return null;
    final digit = (brut["digit"] as num?)?.toInt();
    if (digit == null) return null;
    return IvrOption(
      digit: digit,
      label: brut["label"] as String? ?? "Service $digit",
      // Absent = disponible : un serveur plus ancien ne connaît pas ce champ,
      // et griser toutes les options serait pire que de laisser essayer.
      disponible: brut["disponible"] as bool? ?? true,
      // Une chaîne vide vaut absence : le serveur normalise déjà, mais un serveur
      // plus ancien — ou une donnée saisie autrement — ne le ferait pas, et un
      // nom vide afficherait une ligne blanche sous le nom du centre.
      nomService: _texteOuNull(brut["nomService"]),
    );
  }

  static String? _texteOuNull(dynamic brut) {
    final s = brut is String ? brut.trim() : "";
    return s.isEmpty ? null : s;
  }

  static List<IvrOption> listeDepuisJson(dynamic brut) {
    if (brut is! List) return const [];
    return brut
        .map(IvrOption.depuisJson)
        .whereType<IvrOption>()
        .toList(growable: false);
  }
}

/// Ce que le client sait d'un appel en cours vers un standard.
///
/// ⚠️ On n'y trouvera JAMAIS l'identité d'un agent. Le serveur n'en envoie
/// aucune, et c'est la seule garantie qui tienne : un identifiant qui arrive
/// jusqu'au client est un identifiant public, même s'il n'est pas affiché.
class IvrSession {
  IvrSession({
    required this.callId,
    required this.centerId,
    required this.centerName,
    this.centerNumber,
    this.promptUrl,
    this.holdUrl,
    this.queueUrls = const [],
    required this.options,
  });

  final String callId;
  final String centerId;
  final String centerName;
  final String? centerNumber;

  /// Les trois peuvent être nuls : l'écran doit rester utilisable en silence.
  final String? promptUrl;
  final String? holdUrl;
  final List<String> queueUrls;

  List<IvrOption> options;
  IvrEtape etape = IvrEtape.menu;

  /// Libellé du service choisi, pendant que l'agent sonne.
  String? serviceChoisi;

  /// `nom_service` du service choisi, ou nul si la colonne est vide.
  ///
  /// Affiché sous le nom du centre pendant la mise en relation — et **rien**
  /// n'est affiché quand il est nul, à la demande du user. C'est pour cela qu'il
  /// est distinct de [serviceChoisi] : replier sur le libellé ici mettrait un
  /// nom interne sous les yeux de l'appelant.
  String? nomServiceChoisi;

  /// Dernier message du serveur (« … n'est pas encore disponible »).
  String? message;

  /// Touche envoyée, réponse pas encore arrivée → clavier verrouillé.
  bool envoiEnCours = false;
}

/// Appels directs et de groupe — mesh WebRTC (une connexion par participant).
class CallController extends ChangeNotifier {
  CallController(this._calls, this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final CallsRepository _calls;
  final RealtimeClient _rt;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _ringTimeout;

  /// Délai de lecture d'un message de fin du standard, avant de raccrocher.
  ///
  /// Le serveur n'envoie jamais `ivr_error` ET `call_ended` : le second
  /// fermerait l'écran avant que le premier ne soit lu. C'est donc au client de
  /// tenir l'écran ouvert le temps du message.
  Timer? _finIvr;

  /// Délai accordé à la négociation UNE FOIS l'appel décroché.
  ///
  /// `_ringTimeout` ne couvre que la sonnerie : passé le décrochage, plus rien
  /// ne bornait l'attente et un appel dont le média ne s'établissait pas
  /// affichait « Connexion en cours… » indéfiniment. Le modèle de référence
  /// borne cette phase à 30 s puis annonce l'échec — mieux vaut une fin claire
  /// qu'un écran qui ment.
  Timer? _connectingTimeout;

  String? myUserId;
  String? myDisplayName;

  IncomingCallInfo? incoming;

  /// Standard en cours, ou nul. Non nul ⇒ l'appel sortant a été intercepté par
  /// un centre d'appels et l'écran d'appel affiche le menu à la place.
  IvrSession? ivr;

  /// `idHist` reçu via `queue_rating_available`, en attente d'être montré.
  ///
  /// Ne PAS le vider dans `_clear()` : le message serveur arrive quasi
  /// toujours après notre propre nettoyage local (voir le handler). Consommé
  /// une seule fois par [consumePendingRating], appelé par l'écran d'appel
  /// juste après s'être refermé.
  String? _pendingRatingIdHist;

  /// Lit puis efface l'évaluation en attente — à appeler au plus une fois par
  /// appel, après la fermeture de l'écran.
  String? consumePendingRating() {
    final v = _pendingRatingIdHist;
    _pendingRatingIdHist = null;
    return v;
  }

  String? activeCallId;
  String? activeConvId;
  String? activePeerName;
  String? activePeerAvatarUrl;
  /// Centre qui a routé l'appel EN COURS vers moi (agent) — voir
  /// [IncomingCallInfo.ivrFromId]. Nul pour un appel ordinaire, ou pour un
  /// appel décroché depuis l'écran natif application tuée (`acceptById` n'a
  /// pas cette information, seule la trame WebSocket la porte).
  String? activeIvrFromId;
  String? activeIvrFromName;
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
  // Qui a fait venir qui, renseigné par `call_state "inviting"` : clé =
  // l'invité, valeur = celui qui l'a invité.
  //
  // Sert à décider si le NOM d'un invité peut être montré. Quand B transfère
  // son appel à C, A n'a pas choisi C, ne le connaît pas et n'a aucune raison
  // d'apprendre son identité : pour lui, ce sera « Invité ». Celui qui a lancé
  // l'invitation, lui, voit le nom.
  final Map<String, String> _inviteParUserId = {};

  /// Correspondant d'ORIGINE d'un appel engagé en tête-à-tête, ou nul si
  /// l'appel était un groupe dès le départ.
  ///
  /// Il reste le visage de l'appel même après avoir passé la main : c'est lui
  /// qu'on a appelé, ou qui nous a appelés.
  String? get correspondantOrigineId {
    final autres = _initialMemberIds.where((id) => id != myUserId).toList();
    return autres.length == 1 ? autres.first : null;
  }

  /// Est-ce MOI qui ai fait venir cette personne ?
  bool jaiInvite(String userId) => _inviteParUserId[userId] == myUserId;

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

  /// Vrai quand l'appel entrant est porté par l'ÉCRAN NATIF plein écran.
  ///
  /// L'interface s'en sert pour ne pas superposer son bandeau interne : celui-ci
  /// n'est plus qu'un repli, pour les appareils où la déclaration au système
  /// échoue. Mieux vaut un bandeau que pas d'appel du tout.
  bool ecranNatifAffiche = false;

  // Lot 2b — minimisation : l'écran plein-écran d'appel est-il affiché ?
  // Quand false pendant un appel actif, on montre le bandeau global.
  // Dérivé du compteur `_ecransAppelOuverts` — voir `setCallScreenVisible`.
  bool get callScreenVisible => _ecransAppelOuverts > 0;
  // Début de la connexion média (source unique pour le minuteur, écran + bandeau).
  DateTime? connectedSince;

  // Lot 4 — transfert supervisé : on a invité une cible et on attend qu'elle
  // rejoigne pour quitter automatiquement.
  bool _pendingTransfer = false;
  String? _transferTargetId;
  bool get isTransferring => _pendingTransfer;
  Timer? _transferTimeout;

  /// Nombre d'écrans d'appel affichés, et non un simple booléen.
  ///
  /// ⚠️ L'écran d'appel peut être empilé deux fois — l'utilisateur revient par
  /// le bandeau pendant qu'une ouverture automatique est en cours, par exemple.
  /// Avec un booléen, le `dispose` du premier écran remettait `false` alors que
  /// le second était toujours affiché : le bandeau global réapparaissait
  /// PAR-DESSUS l'écran d'appel.
  ///
  /// Un compteur ne retombe à zéro que lorsque le dernier écran est parti.
  int _ecransAppelOuverts = 0;

  void setCallScreenVisible(bool v) {
    final avant = callScreenVisible;
    if (v) {
      _ecransAppelOuverts++;
    } else if (_ecransAppelOuverts > 0) {
      _ecransAppelOuverts--;
    }
    if (callScreenVisible == avant) return;
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
    traceAppel("APPEL SORTANT cree ${started.id} — moi=$myUserId");
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
    _inviteParUserId.clear();
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

  /// Rappelle un client SOUS LE NOM DU CENTRE (demande user 15/08/2026),
  /// depuis l'écran « Clients abandonnés ». Même déroulé que [startOutgoing]
  /// — seule la création de l'appel diffère (`/api/queue/callback` au lieu de
  /// `/api/calls`) : le reste (mesh, sonnerie sortante, minuteur) est
  /// identique, l'agent est ici aussi l'appelant réel.
  Future<void> startCallback(
      String centerAlanyaID, String customerId, String title) async {
    if (isBusy) {
      lastError = "Termine l'appel en cours avant d'en lancer un autre";
      notifyListeners();
      throw StateError("BUSY");
    }
    lastError = null;
    final started = await _calls.callback(centerAlanyaID, customerId);
    _rt.callRing(started.id);
    activeCallId = started.id;
    activeConvId = started.convId;
    isGroupCall = false;
    isCallInitiator = true;
    activePeerName = title;
    activePeerAvatarUrl =
        started.callees.isNotEmpty ? started.callees.first.avatarUrl : null;
    activeType = "AUDIO";
    activeRole = ActiveCallRole.outgoing;
    participantNames.clear();
    joinedParticipantIds.clear();
    invitedParticipantIds.clear();
    _initialMemberIds.clear();
    _inviteParUserId.clear();
    if (myUserId != null) {
      joinedParticipantIds.add(myUserId!);
      _initialMemberIds.add(myUserId!);
    }
    for (final c in started.callees) {
      participantNames[c.userId] = c.pseudo ?? c.publicNumber ?? "Membre";
      if (c.avatarUrl != null) participantAvatars[c.userId] = c.avatarUrl!;
      _initialMemberIds.add(c.userId);
    }
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 60), () {
      if (activeRole == ActiveCallRole.outgoing && activeCallId != null) {
        hangUp();
      }
    });
    RingtoneService.instance.startOutgoing();
    notifyListeners();
    try {
      await _ensureMesh();
    } catch (e) {
      await RingtoneService.instance.stop();
      await _calls.end(started.id);
      _rt.callState(started.id, "ended",
          userId: myUserId, displayName: myDisplayName);
      _clear();
      rethrow;
    }
    notifyListeners();
  }

  /// Envoie une touche au standard.
  ///
  /// Le clavier se verrouille jusqu'à la réponse du serveur : sur un réseau
  /// lent, l'utilisateur insiste, et deux appuis lanceraient deux sonneries
  /// d'agent pour une seule intention. Le serveur tient la même garde de son
  /// côté — celle-ci n'est que le confort qui évite d'en arriver là.
  ///
  /// On envoie même une touche marquée indisponible : c'est le serveur qui dit
  /// pourquoi, et son message est plus juste que tout ce qu'on pourrait deviner
  /// ici.
  Future<void> envoyerToucheIvr(int digit) async {
    final session = ivr;
    if (session == null || session.etape != IvrEtape.menu) return;
    if (session.envoiEnCours) return;
    session.envoiEnCours = true;
    session.message = null;
    notifyListeners();
    // L'invite s'arrête à l'appui : la laisser courir sous la musique d'attente
    // donnerait deux sons superposés.
    await RingtoneService.instance.stopIvr();
    _rt.ivrDtmf(session.callId, digit);
  }

  Future<void> acceptIncoming() async {
    final inc = incoming;
    if (inc == null || myUserId == null) return;

    // ⚠️ MÊME GARDE QUE `acceptById`, et pour la même raison. Ces deux méthodes
    // acceptent le même appel par des chemins différents — l'interface pour
    // celle-ci, l'écran natif pour l'autre — et peuvent partir presque en même
    // temps au démarrage. Le garde n'existait que dans `acceptById` : ce chemin
    // -ci restait donc exposé au 409 ALREADY_JOINED qui détruisait un appel
    // pourtant établi.
    if (activeCallId == inc.callId) return;
    if (_acceptationEnCours == inc.callId) return;
    _acceptationEnCours = inc.callId;

    // Coupe la sonnerie entrante dès qu'on accepte.
    await RingtoneService.instance.stop();
    PushService.instance.cancelIncomingCall(inc.callId); // retire la notif
    // Fait passer l'écran natif de « appel entrant » à « appel en cours ».
    // Sans cela il garde ses boutons Répondre / Refuser pendant toute la
    // communication et ne réagit plus à rien.
    CallUiNative.marquerConnecte(inc.callId);

    final AcceptCallResult result;
    try {
      result = await _calls.accept(inc.callId);
    } on ApiException catch (e) {
      _acceptationEnCours = null;
      // Déjà accepté par l'autre chemin : la communication EST établie. On
      // aligne l'état local et on laisse la suite se faire — surtout pas de
      // `_clear()`, qui couperait un appel en cours.
      if (e.code == "ALREADY_JOINED") {
        activeCallId = inc.callId;
        activeConvId = inc.convId;
        activePeerName = inc.displayTitle;
        activeIvrFromId = inc.ivrFromId;
        activeIvrFromName = inc.ivrFrom;
        activeType = inc.callType;
        activeRole = ActiveCallRole.ongoing;
        incoming = null;
        notifyListeners();
        await _ensureMesh();
        notifyListeners();
        return;
      }
      // Vraie fin : appelant qui a renoncé, délai expiré, appel déjà clos.
      lastError = "Cet appel n'est plus disponible";
      _clear();
      notifyListeners();
      return;
    } catch (_) {
      // Réseau coupé pendant la requête. Sans ce filet, l'exception remontait
      // et laissait l'état à mi-chemin : sonnerie coupée, notification retirée,
      // mais ni appel actif ni appel entrant — plus aucun moyen d'en sortir.
      _acceptationEnCours = null;
      lastError = "Impossible de rejoindre l'appel";
      _clear();
      notifyListeners();
      return;
    }
    _acceptationEnCours = null;
    isGroupCall = result.isGroup || inc.isGroup;
    isCallInitiator = false;
    activeCallId = inc.callId; // activeCallId défini AVANT incoming = null
    activeConvId = inc.convId;
    activePeerName = inc.displayTitle;
    activeIvrFromId = inc.ivrFromId;
    activeIvrFromName = inc.ivrFrom;
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
    _inviteParUserId.clear();
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
    traceAppel(
        "acceptIncoming — moi=$myUserId, participants actifs renvoyes par /accept : "
        "${result.activeParticipants.map((p) => p.userId).toList()}, mesh=${_mesh != null ? "pret" : "ABSENT"}");
    for (final p in result.activeParticipants) {
      if (p.userId != myUserId) {
        // J'ARRIVE dans l'appel : ceux qui y sont déjà m'enverront leur offre.
        await _mesh?.connectToPeer(p.userId, asOfferer: false);
      }
    }
    // La mesh existe enfin : rejouer l'offre arrivée pendant sa construction.
    await _viderTamponSignaux(inc.callId);
    _armerMinuteurConnexion();
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
  /// Acceptation en cours, pour empêcher deux tentatives simultanées.
  ///
  /// ⚠️ DEUX CHEMINS acceptent le même appel au démarrage : la reprise qui lit
  /// les appels natifs actifs, et l'événement du paquet. Les deux partent
  /// presque en même temps, si bien que le garde `activeCallId == callId` ne
  /// suffit pas — aucun des deux n'a encore eu le temps de le renseigner.
  String? _acceptationEnCours;

  Future<bool> acceptById(String callId, {String? nomAffiche}) async {
    if (myUserId == null) return false;
    // Un appel déjà en cours signifie que la trame est arrivée entre-temps et
    // que le chemin normal a fait le travail : ne rien refaire.
    if (activeCallId == callId) return true;
    if (_acceptationEnCours == callId) return true;
    _acceptationEnCours = callId;

    await RingtoneService.instance.stop();
    PushService.instance.cancelIncomingCall(callId);

    try {
      final result = await _calls.accept(callId);
      isGroupCall = result.isGroup;
      isCallInitiator = false;
      activeCallId = callId;
      activePeerName =
          result.groupName ?? nomAffiche ?? activePeerName ?? "Appel";
      activeRole = ActiveCallRole.ongoing;
      incoming = null;
      // Même raison que dans `acceptIncoming` : sans ce signal, l'écran natif
      // reste sur « appel entrant » pendant toute la communication.
      CallUiNative.marquerConnecte(callId);

      _initialMemberIds
        ..clear()
        ..add(myUserId!);
      joinedParticipantIds
        ..clear()
        ..add(myUserId!);
      for (final p in result.activeParticipants) {
        participantNames[p.userId] = p.displayName;
        // La photo ne pouvait venir que de l'événement WebSocket d'appel
        // entrant — jamais reçu quand on décroche application fermée. L'écran
        // restait donc sans avatar dans ce cas précis, alors qu'il en affiche
        // un quand l'application était ouverte. `/accept` la fournit désormais.
        final avatar = p.avatarUrl;
        if (avatar != null && avatar.isNotEmpty) {
          participantAvatars[p.userId] = avatar;
        }
        joinedParticipantIds.add(p.userId);
        _initialMemberIds.add(p.userId);
        // Sans correspondant nommé, l'écran afficherait « Appel » : le premier
        // participant actif qui n'est pas moi est l'interlocuteur.
        if (p.userId != myUserId && !result.isGroup) {
          if (nomAffiche == null) activePeerName = p.displayName;
          // L'avatar principal suit le correspondant, que son nom vienne du
          // serveur ou de l'écran natif.
          if (avatar != null && avatar.isNotEmpty) activePeerAvatarUrl = avatar;
        }
      }

      _rt.callState(callId, "joined",
          userId: myUserId, displayName: myDisplayName);
      notifyListeners();

      await _ensureMesh();
      traceAppel(
          "acceptById — moi=$myUserId, participants actifs renvoyes par /accept : "
          "${result.activeParticipants.map((p) => p.userId).toList()}, mesh=${_mesh != null ? "pret" : "ABSENT"}");
      for (final p in result.activeParticipants) {
        // Même règle que dans `acceptIncoming` : j'arrive, je ne suis pas
        // l'offreur — ceux déjà présents m'offriront.
        if (p.userId != myUserId) {
          await _mesh?.connectToPeer(p.userId, asOfferer: false);
        }
      }
      // Même raison que dans `acceptIncoming` : l'offre de l'appelant est déjà
      // arrivée, et elle attend dans le tampon.
      await _viderTamponSignaux(callId);
      _armerMinuteurConnexion();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      // ⚠️ ALREADY_JOINED N'EST PAS UN ÉCHEC. Il signifie que l'autre chemin a
      // déjà accepté cet appel — la communication est donc ÉTABLIE. La version
      // précédente traitait tout 409 comme une perte et appelait `_clear()`,
      // ce qui détruisait un appel en cours : l'audio passait, le minuteur
      // tournait dans la notification, et l'application annonçait pourtant
      // « Cet appel n'est plus disponible » sans ouvrir l'écran.
      if (e.code == "ALREADY_JOINED") {
        activeCallId = callId;
        activeRole = ActiveCallRole.ongoing;
        // ⚠️ Ce chemin ne renseignait AUCUN nom, et c'est ce qui affichait
        // « Contact » à la place du correspondant. La cascade de l'écran
        // d'appel — `participantNames`, puis `activePeerName`, puis
        // `incoming.displayTitle` — ne trouvait rien et retombait sur son
        // dernier repli.
        //
        // Le nom est pourtant disponible : l'écran d'appel natif nous l'a
        // passé dans `nomAffiche`. On le retient donc AVANT d'effacer
        // `incoming`, dont le titre sert de second recours.
        activePeerName = nomAffiche ?? incoming?.displayTitle ?? activePeerName;
        activePeerAvatarUrl ??= incoming?.callerAvatarUrl;
        incoming = null;
        CallUiNative.marquerConnecte(callId);
        notifyListeners();
        return true;
      }
      // Les autres 409 sont de vraies fins : appelant qui a renoncé pendant le
      // démarrage, délai expiré, appel déjà clos.
      lastError = "Cet appel n'est plus disponible";
      _clear(idAppel: callId);
      notifyListeners();
      return false;
    } catch (_) {
      lastError = "Cet appel n'est plus disponible";
      _clear(idAppel: callId);
      notifyListeners();
      return false;
    } finally {
      _acceptationEnCours = null;
    }
  }

  Future<void> rejectIncoming() async {
    final inc = incoming;
    if (inc == null) return;
    // Coupe la sonnerie entrante dès qu'on rejette.
    await RingtoneService.instance.stop();

    // ⚠️ L'ÉCHEC NE DOIT PAS INTERROMPRE LA SORTIE. Sans ce try/catch, une
    // coupure réseau ou un appel déjà expiré faisait remonter l'exception AVANT
    // la remise à zéro : la sonnerie était coupée, la notification retirée,
    // mais `incoming` restait posé — l'appel semblait figé, sans moyen d'en
    // sortir. Refuser est une décision de l'utilisateur : elle s'applique
    // localement même si le serveur ne répond pas.
    try {
      await _calls.reject(inc.callId);
    } catch (e) {
      DebugOverlay.log("CC ❌ refus non transmis : $e");
    }
    _rt.callState(
      inc.callId,
      inc.isGroup ? "declined" : "rejected",
      userId: myUserId,
      displayName: myDisplayName,
    );
    _signalBuffer.remove(inc.callId);
    // `_clear()` plutôt qu'un `incoming = null` isolé : c'est LE point de sortie
    // commun à toutes les fins d'appel. Il coupe la sonnerie, retire la
    // notification, ferme l'écran natif, rend la main au verrouillage et arrête
    // le service de premier plan. En s'en passant, ce chemin laissait
    // l'application accessible écran verrouillé et l'écran natif affiché après
    // un refus.
    _clear();
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
      // `id` explicitement : `activeCallId` vient d'être neutralisé ci-dessus.
      _clear(idAppel: id);
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

  /// [idAppel] : identifiant à refermer, quand l'appelant l'a déjà neutralisé.
  ///
  /// ⚠️ `hangUp` met `activeCallId` à `null` AVANT d'appeler ce nettoyage, pour
  /// bloquer les échos entrants. `incoming` étant lui aussi nul sur un appel
  /// décroché, il ne restait ici plus aucun identifiant : l'écran natif n'était
  /// jamais refermé. La notification d'appel survivait donc au raccrochage,
  /// minuteur compris, et le paquet gardait l'appel dans ses « appels actifs ».
  /// La reprise au démarrage y retrouvait alors un appel fantôme et tentait de
  /// l'accepter — d'où « Cet appel n'est plus disponible » à l'appel suivant.
  void _clear({String? idAppel}) {
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _finIvr?.cancel();
    _finIvr = null;
    // Le standard meurt avec l'appel. `_clear` étant le point de passage de
    // TOUTES les fins d'appel, c'est le seul endroit où l'oubli est impossible.
    ivr = null;
    RingtoneService.instance.stopIvr();
    _annulerMinuteurConnexion();
    // Filet de sécurité : coupe toute sonnerie encore en cours.
    // (Doublon sûr des stop() éparpillés — mieux vaut couper 2 fois que 0.)
    RingtoneService.instance.stop();
    final idAFermer = idAppel ?? activeCallId ?? incoming?.callId;
    PushService.instance.cancelIncomingCall(idAFermer); // retire la notif
    // Referme aussi l'ÉCRAN D'APPEL NATIF. Sans cela il continuerait de sonner
    // par-dessus le verrouillage alors que l'appelant a déjà raccroché : le
    // paquet ne sait pas que l'appel est terminé, personne ne le lui a dit.
    if (idAFermer != null) CallUiNative.masquer(idAFermer);
    // Rend la main au verrouillage : sans ce retour, l'application resterait
    // accessible écran verrouillé bien après la fin de l'appel.
    LockScreenCall.desactiver();
    // Relâche les verrous CPU et Wi-Fi, et retire la notification persistante.
    // `_clear` est le point de passage de TOUTES les fins d'appel — raccroché,
    // refusé, expiré, terminé d'en face : c'est le seul endroit où l'arrêt ne
    // peut pas être oublié.
    CallForegroundService.arreter();
    incoming = null;
    activeCallId = null;
    activeConvId = null;
    activePeerName = null;
    activeIvrFromId = null;
    activeIvrFromName = null;
    activePeerAvatarUrl = null;
    participantAvatars.clear();
    activeRole = null;
    isGroupCall = false;
    isCallInitiator = false;
    participantNames.clear();
    joinedParticipantIds.clear();
    invitedParticipantIds.clear();
    _initialMemberIds.clear();
    _inviteParUserId.clear();
    remoteRinging = false;
    /*
     * ⚠️ LA ROUTE AUDIO SE REMET AUSSI, PAS SEULEMENT LE DRAPEAU.
     *
     * Le drapeau seul suffisait tant que le haut-parleur était rare : depuis que
     * tout appel à un centre l'allume, un appel ordinaire suivant aurait
     * démarré avec le bouton affiché « écouteur » et le son sortant en fait par
     * le haut-parleur — un décalage entre ce qu'on montre et ce qu'on fait, qui
     * se paierait la première fois qu'on appelle quelqu'un en public.
     */
    if (isSpeakerOn) {
      isSpeakerOn = false;
      unawaited(Helper.setSpeakerphoneOn(false).catchError((_) {}));
    }
    // Relâché sans condition : l'appel est fini, et un verrou oublié
    // éteindrait l'écran au premier objet passant devant le capteur.
    unawaited(ProximiteAppel.regler(false));
    connectedSince = null;
    // Remise à zéro du compteur : l'appel est fini, plus aucun écran ne le
    // concerne. Les `dispose` qui suivront décrémenteraient dans le vide, ce
    // que `setCallScreenVisible` absorbe en ne descendant jamais sous zéro.
    _ecransAppelOuverts = 0;
    _pendingTransfer = false;
    _transferTargetId = null;
    _transferTimeout?.cancel();
    _transferTimeout = null;
    notifyListeners();
  }

  // Démarre le minuteur dès que le média est réellement connecté.
  void _onMeshUpdated() {
    if (mediaConnected && connectedSince == null) {
      connectedSince = DateTime.now();
      // Le média circule : la négociation a abouti, le délai n'a plus lieu d'être.
      _annulerMinuteurConnexion();
      // Le média circule : à partir d'ici, l'appel doit survivre à un écran
      // éteint ou à un passage en arrière-plan. Démarré ICI et non à
      // l'acceptation — tant qu'aucun flux n'est établi, il n'y a rien à
      // protéger, et la notification persistante ferait doublon avec celle de
      // l'appel entrant.
      CallForegroundService.demarrer(
        titre: activePeerName ?? "Appel en cours",
      );
    }
    // Ce rappel porte AUSSI les changements de caméra : c'est donc le bon
    // endroit pour réévaluer la proximité, qu'il s'agisse de la connexion du
    // média ou d'un passage audio ↔ vidéo en cours d'appel.
    _majProximite();
    notifyListeners();
  }

  // --- Contrôles média (Lot 1) ---
  void toggleMute() {
    final m = _mesh;
    if (m == null) return;
    m.setMic(!m.micEnabled);
    notifyListeners();
  }

  Future<void> toggleSpeaker() => _appliqueHautParleur(!isSpeakerOn);

  Future<void> _appliqueHautParleur(bool actif) async {
    isSpeakerOn = actif;
    try {
      await Helper.setSpeakerphoneOn(actif);
    } catch (_) {}
    _majProximite();
    notifyListeners();
  }

  /// Verrou de proximité : écran éteint ET tactile ignoré quand le téléphone
  /// est à l'oreille.
  ///
  /// Il n'est tenu que dans le seul cas où il protège : conversation établie,
  /// en audio, à l'écouteur.
  ///
  ///  * au HAUT-PARLEUR, le téléphone est posé ou tenu à distance — l'éteindre
  ///    parce qu'une main passe devant le capteur serait une gêne, pas une
  ///    protection ;
  ///  * en VIDÉO, l'utilisateur regarde l'écran, c'est tout l'objet de l'appel ;
  ///
  /// ⚠️ LE TYPE D'APPEL SE LIT SUR [activeType], PAS SUR [isVideoEnabled].
  /// Ce dernier retombe sur `_mesh.cameraEnabled`, qui vaut `true` DÈS LE
  /// DÉPART (`webrtc_group_mesh.dart:42`) et n'est modifié que par `setCamera`.
  /// Dans un appel audio aucune caméra n'est jamais démarrée, le drapeau reste
  /// donc à `true` — et la première version de ce code n'a jamais tenu le
  /// verrou, en croyant chaque appel audio filmé.
  ///  * AVANT la connexion du média, il n'y a encore rien à protéger, et
  ///    l'utilisateur manipule justement son écran.
  ///
  /// Appelé depuis les trois endroits qui changent l'une de ces conditions,
  /// plus la fin d'appel. [ProximiteAppel] absorbe les répétitions.
  void _majProximite() {
    final vise = mediaConnected && !isSpeakerOn && activeType != "VIDEO";
    traceAppel("proximité → $vise (média=$mediaConnected, "
        "hp=$isSpeakerOn, type=$activeType)");
    unawaited(ProximiteAppel.regler(vise));
  }

  /// 🐛 LE STANDARD ALLUME LE HAUT-PARLEUR, ET C'EST UN CORRECTIF, PAS UN CONFORT.
  ///
  /// Symptôme rapporté le 12/08/2026 : « quand j'appelle ça ne sonne pas, c'est
  /// quand j'active puis réactive le haut-parleur que la musique commence ». Les
  /// traces ont montré que la lecture DÉMARRAIT normalement, sans erreur — le son
  /// était produit, mais envoyé à l'ÉCOUTEUR, ce minuscule haut-parleur qu'on
  /// colle à l'oreille. L'audio du standard part sur le flux voix
  /// (`usageType: voiceCommunication`), et WebRTC, déjà en mode conversation,
  /// route ce flux vers l'écouteur. Or personne ne tient son téléphone contre
  /// l'oreille pendant qu'il regarde un pavé numérique pour choisir un service.
  ///
  /// ⚠️ **ON NE REVIENT PLUS À L'ÉCOUTEUR AU DÉCROCHAGE** (règle du user, 12/08) :
  /// « par défaut le son sort par le haut-parleur, et c'est à l'utilisateur de
  /// basculer à l'écouteur lors de l'appel d'un centre ». Le retour automatique
  /// que j'avais posé la remplaçait par une décision de l'application, au pire
  /// moment : l'agent se met à parler dans un téléphone tenu à la main, et sa
  /// première phrase se perd le temps qu'on comprenne pourquoi.
  ///
  /// Rien à défaire non plus si l'appelant coupe le haut-parleur pendant le
  /// menu : plus personne ne le rallume derrière lui.
  Future<void> _hautParleurPourStandard() async {
    if (isSpeakerOn) return;
    await _appliqueHautParleur(true);
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

  /// Traduit un code de raison renvoyé par `call_invite_result` en message
  /// affichable.
  String _inviteErrorText(String? reason) {
    switch (reason) {
      case "NOT_FOUND":
        return "Numéro introuvable";
      case "ALREADY_IN":
        return "Ce correspondant est déjà dans l'appel";
      case "BLOCKED":
        return "Ce correspondant vous a bloqué";
      default:
        return "Invitation impossible";
    }
  }

  // --- Lot 4 : transfert d'appel supervisé ---
  /// Invite `publicNumber` dans l'appel puis, dès qu'il rejoint, quitte
  /// automatiquement (l'appel continue entre le correspondant et l'invité).
  ///
  /// L'identité de la cible est apprise de deux manières redondantes pour
  /// éviter la course qui laissait l'initiateur `leftAt = null` côté serveur :
  ///  1. l'accusé direct `call_invite_result` (le plus fiable, porte `userId`) ;
  ///  2. le broadcast `call_state "inviting"` (repli).
  /// Un minuteur annule le transfert si la cible ne rejoint pas.
  void transferCall(String publicNumber) {
    final id = activeCallId;
    if (id == null) return;
    _pendingTransfer = true;
    _transferTargetId = null;
    lastError = null;
    _rt.callInvite(id, publicNumber);
    _armTransferTimeout();
    notifyListeners();
  }

  /// Annule un transfert en cours (utilisateur qui change d'avis, cible qui
  /// refuse ou qui ne répond pas).
  void cancelTransfer({String? reason}) {
    if (!_pendingTransfer) return;
    _transferTimeout?.cancel();
    _transferTimeout = null;
    _pendingTransfer = false;
    _transferTargetId = null;
    if (reason != null) {
      lastError = reason;
    }
    notifyListeners();
  }

  /// Au bout de ce délai sans que la cible ait rejoint, on annule le transfert
  /// et on reste dans l'appel (plutôt que d'attendre éternellement).
  static const _transfertDelai = Duration(seconds: 45);

  void _armTransferTimeout() {
    _transferTimeout?.cancel();
    _transferTimeout = Timer(_transfertDelai, () {
      if (!_pendingTransfer) return;
      DebugOverlay.log("CC ⏱ transfert: la cible n'a pas rejoint, annulation");
      cancelTransfer(reason: "Transfert annulé : la cible n'a pas répondu");
    });
  }

  /// L'initiateur quitte SANS terminer l'appel pour les autres (transfert).
  Future<void> _completeTransfer(String callId) async {
    _transferTimeout?.cancel();
    _transferTimeout = null;
    _pendingTransfer = false;
    _transferTargetId = null;
    activeCallId = null; // bloque les échos pendant le nettoyage

    // Le /leave est ce qui libère l'initiateur côté serveur (pose leftAt). On
    // NE l'avale plus silencieusement : on réessaie, sinon il reste marqué
    // occupé jusqu'à la fin de l'appel.
    var delivered = false;
    for (var attempt = 0; attempt < 3 && !delivered; attempt++) {
      try {
        await _calls.leave(callId);
        delivered = true;
      } catch (e) {
        DebugOverlay.log(
            "CC ❌ /leave de transfert échoué (tentative ${attempt + 1}): $e");
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    _rt.callState(callId, "left", userId: myUserId, displayName: myDisplayName);
    await _stopMesh();
    // Même raison que dans `hangUp` : `activeCallId` vient d'être neutralisé,
    // sans cet identifiant l'écran natif resterait affiché après le transfert.
    _clear(idAppel: callId);
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
        onPeerLost: _onPeerConnectionLost,
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
    //
    // Filet de sécurité : si on n'a pas reçu l'ID de la cible (accusé
    // `call_invite_result` ou broadcast `inviting` perdus/traités dans le
    // mauvais ordre), on déduit qu'il s'agit d'elle si c'est un NOUVEL
    // utilisateur, non membre initial, qui rejoint pendant un transfert.
    // Sans ça, A n'appelait jamais /leave et restait marqué occupé.
    if (_pendingTransfer) {
      final isTarget = _transferTargetId != null && userId == _transferTargetId;
      final isFallbackTarget = _transferTargetId == null &&
          joinedWhileOngoing &&
          isNew &&
          !_initialMemberIds.contains(userId);
      if (isTarget || isFallbackTarget) {
        final id = activeCallId;
        if (id != null) {
          await _completeTransfer(id);
          return;
        }
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
    // QUELQU'UN ARRIVE alors que je suis déjà là : c'est à moi d'offrir.
    // En 1-à-1 cet événement est le décrochage de l'appelé, et c'est donc
    // l'appelant qui offre — le chemin direct, celui qui a toujours marché.
    await _mesh?.connectToPeer(userId, asOfferer: true);
    _armerMinuteurConnexion();
    notifyListeners();
  }

  /// Rejoue les signaux arrivés AVANT que la mesh n'existe.
  ///
  /// ⚠️ C'est le chemin de l'APPELÉ, et il n'en existait aucun. L'appelant émet
  /// son offre dès qu'il apprend le décrochage, or à cet instant l'appelé est
  /// encore dans `acceptIncoming` : sa mesh n'est pas construite, et l'offre
  /// tombe dans `_signalBuffer`. Le seul vidage écrit jusqu'ici se trouvait
  /// dans le handler de `call_state 'joined'` — inaccessible ici, puisque le
  /// « joined » que reçoit l'appelé est LE SIEN et ressort aussitôt par
  /// `_takenByAnotherDevice`. L'offre restait donc dans le tampon pour
  /// toujours ; les candidats ICE, arrivant plus tard, trouvaient la mesh prête
  /// et passaient — d'où un appel qui semblait négocier alors que rien ne
  /// répondait.
  Future<void> _viderTamponSignaux(String callId) async {
    final mesh = _mesh;
    final tampon = _signalBuffer[callId];
    if (mesh == null || tampon == null || tampon.isEmpty) return;
    _signalBuffer.remove(callId);
    traceAppel("tampon rejoue — ${tampon.length} pair(s)");
    for (final parPair in tampon.entries) {
      for (final sig in parPair.value) {
        await mesh.handleSignal(parPair.key, sig);
      }
    }
  }

  /// Arme le délai de négociation. Sans effet si le média circule déjà.
  void _armerMinuteurConnexion() {
    traceAppel(
        "minuteur 30s ARME (media=${mediaConnected ? "deja ok" : "absent"})");
    if (mediaConnected) return;
    _connectingTimeout?.cancel();
    _connectingTimeout = Timer(const Duration(seconds: 30), () {
      if (mediaConnected || activeCallId == null) return;
      traceAppel("30 s sans media etabli → echec de connexion");
      lastError = "Connexion impossible";
      hangUp();
    });
  }

  void _annulerMinuteurConnexion() {
    _connectingTimeout?.cancel();
    _connectingTimeout = null;
  }

  /// Connexion média définitivement perdue avec un pair.
  ///
  /// Le serveur finira par le confirmer quand sa socket tombera, mais il peut
  /// s'écouler des dizaines de secondes : sans cette réaction locale, l'appel
  /// restait affiché alors que plus rien ne circulait. Dernier pair → l'appel
  /// est fini ; sinon on retire ce participant et la communication continue.
  Future<void> _onPeerConnectionLost(String userId) async {
    if (activeCallId == null) return;
    final autres = joinedParticipantIds.where((id) => id != myUserId).toSet();
    if (autres.length <= 1) {
      traceAppel("perte du dernier pair ($userId) → raccrochage");
      lastError = "Connexion perdue";
      await hangUp();
      return;
    }
    traceAppel(
        "perte du pair $userId → l'appel continue a ${autres.length - 1}");
    await _onPeerLeft(userId);
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
        ivrFrom: e["ivrFrom"] as String?,
        ivrFromId: e["ivrFromId"] as String?,
      );
      // COMMENT ANNONCER L'APPEL — cela dépend de l'état de l'application.
      //
      // Application OUVERTE : son bandeau interne et sa sonnerie, comme
      // toujours. L'utilisateur regarde déjà l'écran, il n'y a rien à réveiller
      // et l'interface de l'application est plus soignée que celle du système.
      //
      // Application EN ARRIÈRE-PLAN OU FERMÉE : écran d'appel natif. C'est le
      // cas qui manquait — le bandeau interne y était invisible, et seul le
      // push d'arrière-plan déclarait cet écran, donc uniquement application
      // fermée. Un appel reçu application simplement réduite n'arrivait alors
      // que sous la forme d'une notification ordinaire.
      final auPremierPlan =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

      var natifAffiche = false;
      if (!auPremierPlan) {
        try {
          await CallUiNative.afficherAppelEntrant(
            callId: callId,
            nom: incoming!.displayTitle,
            avatarUrl: incoming!.callerAvatarUrl,
            video: incoming!.callType == "VIDEO",
          );
          natifAffiche = true;
        } catch (e) {
          debugPrint("[CallController] écran d'appel natif indisponible: $e");
        }
      }
      ecranNatifAffiche = natifAffiche;

      // Sonnerie interne dès que l'écran natif ne porte pas l'appel : il joue
      // la sienne, et les deux ensemble donneraient une double sonnerie.
      //
      // ⚠️ `natifAffiche` NE SUFFIT PAS À LE SAVOIR. Il ne dit que ceci : « ai-je
      // déclaré l'appel à l'instant ? » Or au démarrage à froid, c'est le PUSH
      // qui l'a déjà déclaré à Telecom, plusieurs secondes avant que la trame
      // socket n'arrive ici — l'application est alors au premier plan, donc
      // `natifAffiche` vaut faux, et une seconde sonnerie partirait par-dessus
      // celle qui joue déjà.
      //
      // On interroge donc l'état RÉEL du natif. Mesuré sur TECNO KL5 : sans ce
      // contrôle, la sonnerie native était coupée à 3,1 s pour laisser la place
      // à l'interne, qui ne démarrait qu'à 16,0 s — huit secondes de silence.
      if (!natifAffiche) {
        final natifSonneDeja =
            (await AlanyaTelecom.getRingingCall())?['callId']?.toString() ==
                callId;
        if (!natifSonneDeja) {
          RingtoneService.instance.startIncoming();
        } else {
          traceAppel("sonnerie interne ignorée — le natif sonne déjà");
        }
      }
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
      final mesh = _mesh;
      traceAppel(
          "call_signal ${signal["kind"]} recu de $from — mesh=${mesh != null ? "pret" : "ABSENT → tampon"}");
      if (mesh != null) {
        // `await` : deux signaux qui se suivent (offre puis candidats ICE)
        // doivent être appliqués dans leur ordre d'arrivée.
        await mesh.handleSignal(from, signal);
      } else {
        _bufferSignal(callId, from, signal);
      }
    } else if (type == "ivr_menu") {
      // Le serveur répond « voici le menu » au lieu de faire sonner : ce numéro
      // était un centre d'appels. Le client ne l'avait pas demandé et n'avait
      // aucun contrôle à faire avant d'appeler — c'est le serveur qui décide.
      final callId = e["callId"] as String?;
      if (callId == null || callId != activeCallId) return;
      // ⚠️ COUPER LE MINUTEUR DE SONNERIE. `startOutgoing` arme 60 s pour un
      // appel que personne ne décroche ; laissé en place, il raccrocherait
      // l'appelant en plein milieu de son choix.
      _ringTimeout?.cancel();
      _ringTimeout = null;
      // Le bip d'attente sortant n'a plus lieu d'être : personne ne sonne.
      await RingtoneService.instance.stop();
      final rawQueue = e["queueUrls"];
      final queueUrls = rawQueue is List
          ? rawQueue.map((x) => x.toString()).toList()
          : <String>[];
      final session = IvrSession(
        callId: callId,
        centerId: e["centerId"] as String? ?? "",
        centerName: e["centerName"] as String? ?? activePeerName ?? "Standard",
        centerNumber: e["centerNumber"] as String?,
        promptUrl: e["promptUrl"] as String?,
        holdUrl: e["holdUrl"] as String?,
        queueUrls: queueUrls,
        options: IvrOption.listeDepuisJson(e["options"]),
      );
      ivr = session;
      activePeerName = session.centerName;
      final avatarCentre = e["centerAvatarUrl"] as String?;
      if (avatarCentre != null) activePeerAvatarUrl = avatarCentre;
      DebugOverlay.log(
          "CC ☎️ standard ${session.centerName} — ${session.options.length} option(s)");
      notifyListeners();
      // ⚠️ LA ROUTE AUDIO D'ABORD, LA LECTURE ENSUITE. Poser le haut-parleur
      // après avoir lancé l'invite laisserait ses premières secondes sortir par
      // l'écouteur — soit exactement le symptôme qu'on corrige, en plus court.
      await _hautParleurPourStandard();
      final prompt = session.promptUrl;
      // Tracé AVANT la lecture : c'est la seule façon de distinguer « le serveur
      // n'a envoyé aucune invite » de « l'invite n'a pas pu être lue ». Sans
      // cette ligne, les deux se présentent de la même manière — le silence.
      DebugOverlay.log(prompt == null
          ? "CC ☎️ AUCUNE invite envoyée par le serveur"
          : "CC ☎️ invite : $prompt");
      if (prompt != null) {
        unawaited(RingtoneService.instance.playIvrPrompt(prompt, loop: true));
      }
    } else if (type == "ivr_hold") {
      final session = ivr;
      if (session == null || e["callId"] != session.callId) return;
      session.etape = IvrEtape.attente;
      session.serviceChoisi = e["label"] as String?;
      session.nomServiceChoisi = IvrOption._texteOuNull(e["nomService"]);
      session.message = null;
      session.envoiEnCours = false;
      notifyListeners();
      // L'URL est arrivée dès `ivr_menu` : le client a eu toute la durée de
      // l'invite pour la mettre en cache, la musique démarre donc à l'instant
      // de l'appui au lieu de laisser trois secondes de silence.
      final hold = e["holdUrl"] as String? ?? session.holdUrl;
      if (hold != null) unawaited(RingtoneService.instance.playIvrHold(hold, loop: true));
    } else if (type == "ivr_error") {
      final callId = e["callId"] as String?;
      final retry = e["retry"] == true;
      final message =
          e["message"] as String? ?? "Le standard n'a pas pu aboutir";
      await RingtoneService.instance.stopIvr();
      final session = ivr;
      if (session == null || callId != session.callId) {
        // Refus AVANT toute session : le centre n'a aucun service joignable.
        lastError = message;
        notifyListeners();
        await hangUp();
        return;
      }
      final options = IvrOption.listeDepuisJson(e["options"]);
      if (options.isNotEmpty) session.options = options;
      session.message = message;
      session.envoiEnCours = false;
      if (retry) {
        // Un agent occupé, absent ou qui refuse ne raccroche PAS au nez de
        // l'appelant : il revient au menu et choisit un autre service. C'est ce
        // que fait un vrai standard.
        session.etape = IvrEtape.menu;
        session.serviceChoisi = null;
        notifyListeners();

        // Si tous les agents sont occupés et qu'on a des musiques d'attente (vocal_attente),
        // on les joue en boucle pour faire patienter agréablement l'utilisateur.
        final rawQueue = e["queueUrls"];
        final queueList = rawQueue is List
            ? rawQueue.map((x) => x.toString()).toList()
            : session.queueUrls;
        if (e["code"] == "busy" && queueList.isNotEmpty) {
          DebugOverlay.log("CC ☎️ Musique d'attente en boucle (${queueList.length} titre(s))");
          unawaited(RingtoneService.instance.playIvrQueueList(queueList, loop: true));
        }
        return;
      }
      // Fin sans retour possible. Le message reste affiché : le serveur n'envoie
      // volontairement AUCUN `call_ended` avec, sinon l'écran se fermerait dans
      // la même milliseconde et le texte serait illisible. C'est donc à nous de
      // laisser le temps de lire avant de raccrocher.
      notifyListeners();
      _finIvr?.cancel();
      _finIvr = Timer(const Duration(seconds: 4), () {
        if (ivr?.callId == callId) hangUp();
      });
    } else if (type == "queue_rating_available") {
      // Envoyé par le serveur à la clôture d'un appel passé par un centre
      // (voir `handleCallState` de ws-server.mjs), une fois que l'appel a
      // réellement atteint un agent. Arrive quasi toujours APRÈS `_clear()` :
      // notre propre raccrochage nettoie l'état localement avant que le
      // serveur ait fini de traiter l'`ended` qu'on vient de lui envoyer.
      // On garde l'`idHist` sans condition sur l'appel actif ; c'est
      // `ActiveCallScreen` qui décide quand le montrer, après la fermeture
      // de l'écran.
      final idHist = e["idHist"] as String?;
      if (idHist != null) _pendingRatingIdHist = idHist;
    } else if (type == "call_invite_result") {
      // Accusé de réception direct du serveur après un call_invite. C'est le
      // moyen le plus fiable de connaître l'ID de la cible : il arrive même si
      // le broadcast `inviting` est perdu ou traité dans le mauvais ordre.
      final ok = e["ok"] == true;
      final userId = e["userId"] as String?;
      if (_pendingTransfer) {
        if (ok && userId != null && userId != myUserId) {
          _transferTargetId = userId;
        } else if (!ok) {
          final reason = e["reason"] as String?;
          cancelTransfer(reason: _inviteErrorText(reason));
        }
        notifyListeners();
      }
    } else if (type == "call_state") {
      final state = e["state"] as String?;
      final callId = e["callId"] as String?;
      final fromUserId = e["from"] as String?;
      final userId = e["userId"] as String? ?? fromUserId;
      final displayName = e["displayName"] as String?;

      if (callId == null) return;

      // Trace posée AVANT toute garde : c'est le point où l'on saura si
      // l'appelant apprend, ou non, que son correspondant a décroché.
      traceAppel("call_state '$state' de ${userId ?? "?"} — moi=$myUserId, "
          "actif=${callId == activeCallId}, entrant=${callId == incoming?.callId}");

      if (state == "joined" || state == "accepted") {
        // Notre propre identifiant : soit l'écho de notre « joined », soit un
        // autre appareil du même compte qui vient de décrocher — auquel cas il
        // faut couper la sonnerie ici.
        if (userId == myUserId) {
          traceAppel("→ ignore : c'est mon propre identifiant");
          _takenByAnotherDevice(callId);
          return;
        }
        if (callId == activeCallId || callId == incoming?.callId) {
          // Standard : quelqu'un a décroché. La session n'a plus de raison
          // d'être, l'écran redevient un écran d'appel ordinaire — au nom du
          // CENTRE. Le serveur a réécrit `userId` pour nous : le pair qu'on
          // s'apprête à connecter est le centre, jamais l'agent.
          if (ivr != null && callId == ivr!.callId) {
            _finIvr?.cancel();
            _finIvr = null;
            ivr = null;
            unawaited(RingtoneService.instance.stopIvr());
            // ⚠️ LE HAUT-PARLEUR RESTE COMME IL EST. On ne rend pas l'écouteur
            // à la conversation : c'est le choix de l'appelant, pas le nôtre.
          }
          // ⚠️ ATTENDRE la fin de `_onPeerJoined` avant de toucher au tampon.
          // C'est elle qui construit la mesh (`_ensureMesh`) et ouvre la session
          // du pair. Sans `await`, la ligne suivante s'exécutait alors que
          // `_mesh` était encore nul : le tampon était vidé par `remove` puis
          // abandonné faute de mesh où le rejouer, et l'offre SDP disparaissait
          // définitivement. C'est ce qui rendait un sens d'appel systématique-
          // ment muet — l'offreur étant fixé par comparaison d'identifiants,
          // la paire échouait toujours dans le même sens.
          await _onPeerJoined(userId ?? "", displayName);

          // Ne retirer du tampon que ce qu'on est réellement capable de
          // rejouer : si la mesh n'a pas pu être créée (permission refusée,
          // micro indisponible), les signaux restent en attente.
          final mesh = _mesh;
          traceAppel(
              "peer_joined de $userId traite — mesh=${mesh != null ? "pret" : "ABSENT"} tampon=${_signalBuffer[callId]?.length ?? 0} pair(s)");
          if (mesh != null) {
            final bufferedForCall = _signalBuffer.remove(callId);
            for (final peerEntry in bufferedForCall?.entries ??
                const <MapEntry<String, List<Map<String, dynamic>>>>[]) {
              for (final sig in peerEntry.value) {
                await mesh.handleSignal(peerEntry.key, sig);
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
      } else if (state == "locked_elsewhere") {
        // Verrou de conversation : un AUTRE appareil de ce compte a réservé la
        // discussion, et le serveur refuse notre appel sortant.
        //
        // Sans ce cas, l'appel restait à sonner dans le vide jusqu'au délai :
        // le serveur ne le diffusait à personne, et rien ne nous le disait. On
        // raccroche donc tout de suite, avec une raison affichable — c'est la
        // seule façon de comprendre pourquoi ça n'aboutit pas.
        //
        // La réservation ne se périme plus : elle tient jusqu'à ce que le poste
        // qui l'a posée la rende. Inutile de laisser espérer en réessayant.
        if (callId == activeCallId) {
          lastError =
              "Cette conversation est réservée par un autre appareil de ce compte";
          notifyListeners();
          await hangUp();
        }
      } else if (state == "inviting") {
        // Un participant invite quelqu'un : l'inviteur mémorise l'identité de
        // l'invité (pour le transfert supervisé).
        if (_pendingTransfer && userId != null && userId != myUserId) {
          _transferTargetId = userId;
        }
        // Qui a fait venir qui. Seul celui qui invite verra le nom de l'invité
        // — voir `_inviteParUserId`.
        if (userId != null && fromUserId != null) {
          _inviteParUserId[userId] = fromUserId;
        }
      } else if (state == "left" || state == "declined") {
        // Notre propre départ est géré localement dans hangUp — sauf s'il vient
        // d'un autre appareil qui a refusé l'appel pendant qu'on sonne.
        if (userId == myUserId) {
          _takenByAnotherDevice(callId);
          return;
        }
        // Cible du transfert qui refuse/quitte. Le transfert étant en 1-à-1,
        // l'invité qui refuse émet "rejected" ; en groupe il émet "declined".
        // On accepte aussi le cas où on n'a pas encore l'ID cible.
        final isTransferDecline =
            (state == "declined" || state == "rejected") &&
                _pendingTransfer &&
                (_transferTargetId == null || userId == _transferTargetId);
        if (isTransferDecline) {
          cancelTransfer(reason: "Transfert refusé");
          return;
        }
        // La cible a quitté prématurément après avoir rejoint : on annule.
        if (state == "left" &&
            _pendingTransfer &&
            _transferTargetId != null &&
            userId == _transferTargetId) {
          cancelTransfer(reason: "La cible a quitté l'appel");
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
          // L'identifiant vient de l'événement : le troisième cas de
          // `isOurCall` couvre justement un `activeCallId` déjà nul.
          _clear(idAppel: callId);
        }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ringTimeout?.cancel();
    _annulerMinuteurConnexion();
    _stopMesh();
    super.dispose();
  }
}
