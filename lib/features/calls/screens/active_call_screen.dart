import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/authed_api.dart';
import '../../../core/push_service.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/call_rating_sheet.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../chat/screens/chat_screen.dart';
import '../call_controller.dart';
import '../widgets/call_avatar_waves.dart';
import '../widgets/ivr_panel.dart';
import '../widgets/queue_status_sheet.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key, this.incoming = false});

  final bool incoming;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  CallController? _calls;
  Timer? _timer;
  int _elapsed = 0;
  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _renderersReady = false;
  bool _popping = false;
  bool _actionBusy = false;

  // Lot 3 — UI vidéo dynamique (1-1) : quel flux est en plein écran, et
  // position du cadre flottant (PiP) déplaçable.
  bool _localIsMain = false;
  Offset? _pipPos;

  // Lot 6 — polish : auto-masquage des contrôles (vidéo) + drag animé du PiP.
  bool _controlsVisible = true;
  bool _autoHideArmed = false;
  Timer? _hideTimer;
  bool _pipDragging = false;

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onTapScreen(bool autoHideActive) {
    if (!autoHideActive)
      return; // audio / sonnerie : contrôles toujours visibles
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleAutoHide();
  }

  // Instant où l'appel est passé en "ongoing" (décrochage) — base du garde-fou
  // de connexion média (voir _timer).
  DateTime? _ongoingSince;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final cc = _calls;
      if (cc == null || cc.activeRole != ActiveCallRole.ongoing) return;
      // Démarre le chrono de connexion au passage réel en "ongoing" (décrochage),
      // pas à l'ouverture de l'écran — sinon, chez l'appelant, il expirait pendant
      // la sonnerie et ne surveillait jamais la vraie phase de connexion.
      _ongoingSince ??= DateTime.now();
      if (cc.mediaConnected) {
        setState(() => _elapsed++);
      } else if (DateTime.now().difference(_ongoingSince!).inSeconds >= 35) {
        // Le média ne s'est pas connecté 35s après le décrochage → on abandonne.
        showAppSnackBar("Connexion impossible. Vérifie ta connexion réseau.");
        _hangUp(cc);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cc = context.read<CallController>();
    if (_calls == cc) return;
    _calls?.removeListener(_onCallChanged);
    _calls = cc;
    _calls!.addListener(_onCallChanged);
    // Lot 2 : prévient l'appelant que l'écran d'appel est affiché ici
    // (→ « En train de sonner… » chez lui).
    if (widget.incoming) _calls!.notifyRingingDisplayed();
    // Lot 2b : l'écran plein-écran est visible → masque le bandeau global.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calls?.setCallScreenVisible(true);
    });
  }

  void _onCallChanged() {
    if (!mounted) return;
    final cc = _calls;
    if (cc != null && !cc.isBusy) {
      // Lu AVANT de fermer l'écran : `consumePendingRating` ne rend qu'une
      // fois, et un appel sans idHist (jamais atteint un agent) rend nul.
      final idHist = cc.consumePendingRating();
      _popScreen();
      if (idHist != null) _afficherNotePostAppel(idHist);
    }
    if (mounted) _syncStreams();
  }

  /// Affiche la feuille de notation une fois l'écran d'appel refermé.
  ///
  /// ⚠️ Sur le contexte GLOBAL (`PushService.navigatorKey`), pas `context` de
  /// cet écran : `_popScreen()` vient de le retirer de la pile, et un contexte
  /// démonté ne peut plus ouvrir de feuille modale. `addPostFrameCallback`
  /// laisse le temps à l'animation de fermeture de démarrer avant d'empiler
  /// la feuille par-dessus.
  void _afficherNotePostAppel(String idHist) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = PushService.navigatorKey.currentContext;
      if (ctx == null) return;
      CallRatingSheet.show(ctx, idHist: idHist, api: ctx.read<AuthedApi>());
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    if (mounted) setState(() => _renderersReady = true);
    _syncStreams();
  }

  Future<RTCVideoRenderer> _rendererFor(String peerId) async {
    var r = _remoteRenderers[peerId];
    if (r == null) {
      r = RTCVideoRenderer();
      await r.initialize();
      _remoteRenderers[peerId] = r;
    }
    return r;
  }

  void _syncStreams() async {
    if (!_renderersReady || !mounted) return;
    final cc = _calls;
    if (cc == null) return;
    final local = cc.localStream;
    if (_localRenderer.srcObject != local) {
      _localRenderer.srcObject = local;
    }

    final remotes = cc.remoteStreams;
    for (final id in remotes.keys) {
      final r = await _rendererFor(id);
      if (r.srcObject != remotes[id]) {
        r.srcObject = remotes[id];
      }
    }
    final stale =
        _remoteRenderers.keys.where((k) => !remotes.containsKey(k)).toList();
    for (final id in stale) {
      await _remoteRenderers.remove(id)?.dispose();
    }
    if (mounted) setState(() {});
  }

  /// Ferme CET écran, et lui seul.
  ///
  /// ⚠️ `Navigator.pop()` ferme la route DU DESSUS de la pile, qui n'est pas
  /// forcément celle-ci : une feuille de contacts, un menu ou une boîte de
  /// dialogue ouverte par-dessus l'appel se faisait fermer à sa place, et
  /// l'écran d'appel restait affiché sur un appel déjà terminé.
  ///
  /// `_popping` n'était par ailleurs jamais relâché : si la fermeture ne se
  /// produisait pas, l'écran devenait définitivement impossible à refermer.
  /// Il n'est désormais posé qu'une fois la fermeture réellement demandée.
  void _popScreen() {
    if (_popping || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final nav = Navigator.of(context);
    if (route.isCurrent) {
      _popping = true;
      nav.pop();
    } else if (route.isActive) {
      // Une autre route est passée par-dessus : on retire la nôtre de la pile
      // sans toucher à celle qui est au-dessus.
      _popping = true;
      nav.removeRoute(route);
    }
  }

  Future<void> _reject(CallController cc) async {
    if (_actionBusy) return;
    _actionBusy = true;
    try {
      await cc.rejectIncoming();
    } catch (_) {
      showAppSnackBar("Impossible de refuser l'appel");
    } finally {
      _popScreen();
    }
  }

  Future<void> _accept(CallController cc) async {
    if (_actionBusy || _popping) return;
    _actionBusy = true;
    try {
      await cc.acceptIncoming();
      if (mounted) setState(() {});
    } on Object catch (e) {
      showAppSnackBar("Impossible d'accepter l'appel");
      debugPrint("[call] accept: $e");
    } finally {
      if (mounted) _actionBusy = false;
    }
  }

  Future<void> _hangUp(CallController cc) async {
    if (_actionBusy) return;
    _actionBusy = true;
    try {
      await cc.hangUp();
    } catch (_) {
      showAppSnackBar("Erreur lors du raccrochage");
    } finally {
      _popScreen();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hideTimer?.cancel();
    // Lot 2b : l'écran n'est plus affiché → le bandeau reprend si l'appel continue.
    _calls?.setCallScreenVisible(false);
    _calls?.removeListener(_onCallChanged);
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  /// Durée écoulée, calculée depuis `connectedSince` du contrôleur.
  ///
  /// ⚠️ UN COMPTEUR LOCAL REPART À ZÉRO à chaque construction de l'écran. Or
  /// l'écran se referme et se rouvre en cours d'appel — on le réduit, on
  /// revient par le bandeau — et le minuteur recommençait alors à 00:00 tandis
  /// que le bandeau, lui, affichait la vraie durée. Deux chiffres différents
  /// pour le même appel.
  ///
  /// `connectedSince` est la source unique documentée dans le contrôleur : la
  /// lire garantit que les deux affichages concordent toujours.
  String _formatElapsed(CallController cc) {
    final depuis = cc.connectedSince;
    final secondes =
        depuis == null ? 0 : DateTime.now().difference(depuis).inSeconds;
    final m = secondes ~/ 60;
    final s = secondes % 60;
    return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
  }

  /// L'appel AFFICHÉ ICI est-il un appel vidéo ?
  ///
  /// ⚠️ La règle lisait `cc.incoming?.callType ?? cc.activeType`. Or `incoming`
  /// désigne l'appel qui SONNE, pas celui qui est affiché : si un second appel
  /// arrivait pendant une communication audio, son type prenait le dessus et
  /// l'interface basculait en vidéo pour l'appel en cours — caméra allumée
  /// comprise.
  ///
  /// `incoming` n'est donc consulté que tant qu'aucun appel n'est actif, c'est-
  /// à-dire pendant la sonnerie, qui est le cas qu'il servait à couvrir.
  bool _estVideo(CallController cc) {
    final enSonnerie =
        cc.activeRole != ActiveCallRole.ongoing && cc.incoming != null;
    final type = enSonnerie ? cc.incoming!.callType : cc.activeType;
    return type == "VIDEO";
  }

  /// Le pavé du standard est-il à l'écran ?
  ///
  /// Sert à rendre l'en-tête compact pour lui : c'est la seule situation où
  /// l'écran d'appel doit céder de la hauteur à ce qu'il contient. Pendant la
  /// mise en relation, le pavé a disparu au profit du rond de progression —
  /// l'avatar reprend donc sa taille normale.
  ///
  /// 🔴 **LA RÉPONSE VIENT DU PANNEAU LUI-MÊME** (`IvrPanel.afficheLePave`), et
  /// n'est plus redevinée ici. Cette fonction testait `etape == menu` : dès
  /// qu'une étape s'est ajoutée — la lecture d'un centre vocal —, le panneau
  /// montrait le pavé pendant que cet écran croyait le contraire. L'avatar
  /// repassait donc de 64 à 104 points au premier appui sur une touche, et le
  /// pavé, seul `Expanded` de la colonne, payait la différence en rétrécissant.
  /// C'est le défaut signalé par le user le 18/08/2026, de la même famille que
  /// celui du 17/08 : **tout ce qui varie au-dessus du pavé se prend sur lui**.
  bool _menuStandardAffiche(CallController cc) =>
      cc.ivr != null && IvrPanel.afficheLePave(cc.ivr!);

  String _statusText(CallController cc) {
    if (widget.incoming && cc.incoming != null) {
      final inc = cc.incoming!;
      if (inc.isGroup) return "Groupe · ${inc.memberCount} membres";
      return "Appel entrant…";
    }
    // Standard : personne ne sonne tant que l'appelant n'a pas choisi. Laisser
    // « Sonnerie… » dirait exactement le contraire de ce qui se passe.
    final ivr = cc.ivr;
    if (ivr != null) {
      /*
       * 🔴 `ivr.vocal` AUSSI, et pas seulement l'étape « menu » (18/08/2026).
       *
       * Sans lui, la ligne tombait sur `nomServiceChoisi ?? ""` dès qu'un son
       * se mettait à jouer — or ce champ n'est JAMAIS renseigné pour un centre
       * vocal, qui ne met en relation avec personne. Elle rendait donc "" et
       * disparaissait entièrement (le bloc appelant l'omet quand elle est vide,
       * volontairement, pour ne pas laisser un trou sous le nom).
       *
       * Deux dégâts d'un coup : le sous-titre s'évanouissait au premier appui,
       * et sa disparition rendait ~32 points au pavé, qui changeait donc de
       * taille — le second morceau du défaut signalé.
       *
       * Un centre vocal reste un serveur vocal du début à la fin de l'appel :
       * son sous-titre n'a aucune raison de bouger.
       */
      if (ivr.etape == IvrEtape.menu || ivr.vocal) return "Serveur vocal";
      /*
       * Sous le nom du centre : `nom_service`, et RIEN s'il est vide — demande
       * du user du 12/08/2026, qui remplace « Mise en relation — <libelle> ».
       *
       * On ne replie PAS sur `serviceChoisi` : ce serait remettre `libelle`,
       * c'est-à-dire le nom interne de la ligne `center`, sous les yeux de
       * l'appelant. Et l'information « on vous met en relation » n'est pas
       * perdue pour autant — le panneau juste en dessous l'écrit en toutes
       * lettres, sous le rond de progression.
       */
      return ivr.nomServiceChoisi ?? "";
    }
    if (cc.activeRole == ActiveCallRole.outgoing) {
      if (cc.isGroupCall) return "Sonnerie du groupe…";
      return cc.remoteRinging ? "En train de sonner…" : "Sonnerie…";
    }
    if (cc.activeRole == ActiveCallRole.ongoing) {
      if (cc.mediaConnected) return _formatElapsed(cc);
      return "Connexion en cours…";
    }
    return "Connexion en cours…";
  }

  /// [afficheCommeGroupe] et non `cc.isGroupCall` : après un transfert, l'appel
  /// est techniquement multi-partie pendant un instant, mais celui qui reste doit
  /// continuer à vivre un tête-à-tête. Un décompte de participants lui
  /// apprendrait qu'un tiers est entré, ce que le badge « Invité » dit déjà,
  /// sans le nommer.
  String _mediaHint(CallController cc, bool afficheCommeGroupe) {
    if (cc.activeRole != ActiveCallRole.ongoing) return "";
    if (afficheCommeGroupe) {
      return "${cc.connectedPeerCount} connecté(s) · ${cc.joinedParticipantIds.length} dans l'appel";
    }
    if (cc.mediaConnected) {
      // return cc.activeType == "VIDEO" ? "Vidéo connectée" : "Audio connectée";
      return "Appel en cours…";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.watch<CallController>();

    // --- Interlocuteur affiché : calculé depuis les participants RÉELLEMENT
    // présents (pas depuis activePeerName figé) → dès qu'une personne quitte
    // (ex. transfert), son nom disparaît et le nouvel interlocuteur s'affiche.
    final others =
        cc.joinedParticipantIds.where((id) => id != cc.myUserId).toList();
    final invitedOthers =
        others.where((id) => cc.invitedParticipantIds.contains(id)).toList();

    // --- TRANSFERT VU PAR CELUI QUI RESTE ---
    //
    // A appelle B, B transfère à C. Pour A, rien ne doit changer à l'écran : il
    // reste « en communication avec B », le nom et la photo de B sont conservés,
    // et un badge « Invité » signale simplement que quelqu'un d'autre est entré.
    // Le nom de C ne lui est JAMAIS montré — A ne l'a pas choisi, ne le connaît
    // pas, et cette identité ne lui appartient pas.
    //
    // La règle générale est donc : on ne dévoile le nom d'un invité qu'à celui
    // qui l'a fait venir. Quand c'est A lui-même qui invite un tiers dans son
    // appel, il en voit le nom, comme avant.
    final origineId = cc.correspondantOrigineId;
    final inviteParUnAutre = invitedOthers.any((id) => !cc.jaiInvite(id));
    final transfereVersUnInvite = origineId != null && inviteParUnAutre;

    // Interlocuteur principal = le correspondant d'origine s'il est encore là,
    // sinon l'invité restant (cas transfert : l'origine a quitté).
    String? primaryId;
    for (final id in others) {
      if (!cc.invitedParticipantIds.contains(id)) {
        primaryId = id;
        break;
      }
    }
    primaryId ??= others.isNotEmpty ? others.first : null;
    bool primaryInvited =
        primaryId != null && cc.invitedParticipantIds.contains(primaryId);
    // Pastilles « invité » à afficher séparément (invités qui ne sont pas déjà
    // l'interlocuteur principal mis en évidence).
    var invitedChipIds = invitedOthers.where((id) => id != primaryId).toList();
    // Vrai groupe, à distinguer d'un tête-à-tête où un invité est entré : dans
    // ce second cas l'écran garde l'apparence d'un appel direct (photo du
    // correspondant, pas l'icône de groupe).
    var afficheCommeGroupe = cc.isGroupCall;

    if (transfereVersUnInvite) {
      // Le nom et la photo restent ceux de l'origine, même après son départ.
      primaryId = origineId;
      // Un seul badge anonyme, jamais de pastille nominative.
      primaryInvited = true;
      invitedChipIds = const [];
      afficheCommeGroupe = false;
    }

    // Photo de profil pour l'écran d'appel audio (sinon initiale).
    final String? callAvatarUrl = (widget.incoming && cc.incoming != null)
        ? cc.incoming!.callerAvatarUrl
        : (primaryId != null
            ? cc.participantAvatars[primaryId]
            : cc.activePeerAvatarUrl);

    // FIX appel entrant : après décroché, cc.incoming repasse à null (acceptIncoming)
    // alors que widget.incoming reste true. L'ancien code faisait
    // `cc.incoming?.displayTitle ?? "Appel"` → retombait sur "Appel" juste après
    // avoir décroché chez B. On utilise désormais activePeerName / participantNames
    // dès que l'appel n'est plus en sonnerie.
    final String name;
    if (widget.incoming && cc.incoming != null) {
      name = cc.incoming!.displayTitle;
    } else if (primaryId != null) {
      name = cc.participantNames[primaryId] ??
          cc.activePeerName ??
          cc.incoming?.displayTitle ??
          "Contact";
    } else {
      name = cc.activePeerName ?? cc.incoming?.displayTitle ?? "Contact";
    }
    // Après acceptation d'un appel entrant, cc.incoming repasse à null alors que
    // widget.incoming reste true : l'ancien code lisait donc cc.incoming?.callType
    // == null → isVideo=false → l'UI masquait la vidéo (distante ET auto-vue) même
    // pour un appel vidéo. On lit incoming.callType pendant la sonnerie, puis on
    // retombe sur activeType une fois l'appel actif.
    final isVideo = _estVideo(cc);
    final remotes = cc.remoteStreams;
    final showVideo = isVideo &&
        cc.activeRole == ActiveCallRole.ongoing &&
        remotes.isNotEmpty;
    final showIncoming = widget.incoming && cc.incoming != null;
    final showActive = cc.activeCallId != null && cc.activeRole != null;

    // Lot 3 : appel vidéo 1-1 actif → plein écran dynamique (principal + PiP).
    // Les appels de groupe gardent la grille ; l'audio garde l'avatar.
    final useDynamic = isVideo &&
        showActive &&
        !cc.isGroupCall &&
        remotes.length <= 1 &&
        cc.localStream != null;
    RTCVideoRenderer? dynMain;
    bool dynMainMirror = false;
    RTCVideoRenderer? dynPip;
    bool dynPipMirror = false;
    if (useDynamic) {
      final remoteId = remotes.keys.isNotEmpty ? remotes.keys.first : null;
      final remoteR = remoteId != null ? _remoteRenderers[remoteId] : null;
      if (remoteR == null) {
        // Pas encore de flux distant : on affiche sa propre caméra en grand.
        dynMain = _localRenderer;
        dynMainMirror = true;
      } else if (_localIsMain) {
        dynMain = _localRenderer;
        dynMainMirror = true;
        dynPip = remoteR;
      } else {
        dynMain = remoteR;
        dynPip = _localRenderer;
        dynPipMirror = true;
      }
    }

    // Lot 6 : auto-masquage des contrôles pendant un appel vidéo actif.
    final autoHideActive = isVideo && cc.activeRole == ActiveCallRole.ongoing;
    final showControls = !autoHideActive || _controlsVisible;
    if (autoHideActive && !_autoHideArmed) {
      _autoHideArmed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleAutoHide();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Le retour RÉDUIT l'appel, il ne le coupe plus : l'écran se ferme,
        // l'appel continue et le bandeau global prend le relais pour y revenir
        // — exactement ce que fait déjà le bouton « chat ». Pour raccrocher, il
        // reste le bouton rouge, qui est le seul geste explicite.
        //
        // Un appel ENTRANT fait exception : il n'y a rien à réduire tant qu'on
        // n'a pas décroché, et laisser sonner un écran fermé serait pire que
        // refuser. Le retour continue donc d'y valoir refus.
        if (showIncoming) {
          await _reject(cc);
        } else {
          _popScreen();
        }
      },
      child: Scaffold(
        backgroundColor: AlanyaColors.chocolate,
        body: SafeArea(
          child: Stack(
            children: [
              if (useDynamic && dynMain != null)
                Positioned.fill(
                  child: RTCVideoView(
                    dynMain!,
                    mirror: dynMainMirror,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else if (showVideo)
                _remoteGrid(cc, remotes,
                    anonymiseLesInvites: transfereVersUnInvite),
              // Lot 6 : couche de tap plein écran (toggle des contrôles en vidéo).
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _onTapScreen(autoHideActive),
                  child: const SizedBox.expand(),
                ),
              ),
              // Lot 6 : dégradés sombres haut/bas pour la lisibilité en vidéo.
              if (isVideo && (showVideo || useDynamic)) _scrims(showControls),
              AnimatedOpacity(
                opacity: showControls ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !showControls,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Aligné sur le bouton retour : ce bouton RÉDUIT
                          // l'appel au lieu de le couper. Une croix « Fermer »
                          // qui raccroche, à côté d'un retour qui réduit, disait
                          // deux choses différentes du même geste.
                          IconButton(
                            icon: Icon(
                              showIncoming
                                  ? Icons.close
                                  : Icons.keyboard_arrow_down,
                              color: Colors.white70,
                            ),
                            tooltip: showIncoming ? "Refuser" : "Réduire",
                            onPressed: () async {
                              if (showIncoming) {
                                await _reject(cc);
                              } else {
                                _popScreen();
                              }
                            },
                          ),
                          // Uniquement pour un agent EN TRAIN de prendre un appel
                          // routé par un centre (demande user 15/08/2026) — nul
                          // pour un appel ordinaire, ou décroché app tuée
                          // (`acceptById` n'a pas cette info).
                          if (cc.activeIvrFromId != null)
                            IconButton(
                              icon: const Icon(Icons.groups_outlined,
                                  color: Colors.white70),
                              tooltip: "Liste d'attente",
                              onPressed: () {
                                QueueStatusSheet.show(
                                  context,
                                  centerAlanyaID: cc.activeIvrFromId!,
                                  api: context.read<AuthedApi>(),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!showVideo && !useDynamic)
                        // ⚠️ AVATAR RÉDUIT PENDANT LE MENU DU STANDARD, et lui
                        // seul. Le pavé n'occupe que la place que l'en-tête lui
                        // laisse : à 104 px d'avatar, il ne restait pas de quoi
                        // donner aux touches leur taille normale, et les rendre
                        // toutes visibles les rabougrissait. Ce qu'on regarde à
                        // cet instant, c'est le clavier — pas la photo d'un
                        // standard, qui n'a même pas de visage.
                        CallAvatarWaves(
                          diameter: _menuStandardAffiche(cc) ? 64 : 104,
                          // Bleu clair et non vert (demande du user,
                          // 17/08/2026) : le vert du thème se distinguait mal
                          // du fond sombre de l'écran d'appel.
                          color: AlanyaColors.bleuAppel,
                          active: cc.activeRole == ActiveCallRole.ongoing ||
                              cc.activeRole == ActiveCallRole.outgoing,
                          child: afficheCommeGroupe
                              ? CircleAvatar(
                                  radius: _menuStandardAffiche(cc) ? 32 : 52,
                                  backgroundColor: AlanyaColors.terracotta,
                                  child: Icon(Icons.groups,
                                      size: _menuStandardAffiche(cc) ? 30 : 48,
                                      color: Colors.white),
                                )
                              : AvatarCircle(
                                  name: name,
                                  avatarUrl: callAvatarUrl,
                                  radius: _menuStandardAffiche(cc) ? 32 : 52,
                                  backgroundColor: AlanyaColors.terracotta,
                                  textColor: Colors.white,
                                ),
                        ),
                      // Espace avatar → nom, resserré pendant le standard
                      // (demande du user, 17/08/2026) : chaque point repris ici
                      // revient au pavé numérique.
                      if (!showVideo)
                        SizedBox(height: _menuStandardAffiche(cc) ? 6 : 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Interlocuteur actif = un invité (ex. après transfert) :
                      // badge « invité » mis en évidence pour lever l'ambiguïté.
                      if (primaryInvited) ...[
                        const SizedBox(height: 8),
                        _invitedBadge(),
                      ],
                      // Ligne d'état omise ENTIÈREMENT quand elle est vide, et
                      // non rendue avec un texte nul : un `Text("")` occuperait
                      // quand même sa hauteur de ligne, et l'espacement au-dessus
                      // laisserait un trou sous le nom du centre — visible
                      // précisément dans le cas « pas de nom de service ».
                      if (_statusText(cc).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_statusText(cc),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 16)),
                      ],
                      // ── Message du standard, SOUS le libellé du service ──
                      //
                      // Emplacement demandé par le user (17/08/2026) après
                      // l'avoir vu entre l'avatar et le nom : il se lit mieux
                      // rattaché à ce qu'il commente — le service qu'on vient
                      // d'essayer.
                      //
                      // 🔴 **Sa hauteur reste CONSTANTE, et c'est tout l'enjeu**
                      // (voir `IvrMessageBand`). Le pavé numérique prend « ce qui
                      // reste » : si cette bande apparaissait et disparaissait
                      // avec le message, le pavé changerait de taille à chaque
                      // aller-retour vers l'attente — le défaut signalé. Ce qui
                      // compte n'est pas OÙ elle est posée, mais qu'elle occupe
                      // toujours la même place.
                      if (cc.ivr != null)
                        IvrMessageBand(message: cc.ivr!.message),
                      if (cc.activeRole == ActiveCallRole.ongoing) ...[
                        const SizedBox(height: 10),
                        Text(_mediaHint(cc, afficheCommeGroupe),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13)),
                      ],
                      if (cc.lastError != null) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            cc.lastError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.orangeAccent, fontSize: 13),
                          ),
                        ),
                      ],
                      if (invitedChipIds.isNotEmpty &&
                          cc.activeRole == ActiveCallRole.ongoing)
                        _invitedChips(cc, invitedChipIds),
                      // SERVEUR VOCAL — affiché DANS l'écran d'appel, et non sur
                      // un écran à part.
                      //
                      // Le guide recommande un écran dédié atteint par
                      // `pushReplacement`, et met en garde contre les pièges qui
                      // en découlent : écouteurs retirés par le `dispose` de
                      // l'ancien écran, ligne à réoccuper, mode « déjà décroché »
                      // à inventer sur l'écran d'appel. Aucun de ces problèmes
                      // n'existe ici parce qu'on ne change pas d'écran : le
                      // contrôleur tient déjà la ligne, l'abonnement au flux
                      // temps réel lui appartient, et quand l'agent décroche le
                      // panneau disparaît — l'écran d'appel était déjà là.
                      if (cc.ivr != null)
                        Expanded(
                          child: IvrPanel(
                            session: cc.ivr!,
                            onTouche: cc.envoyerToucheIvr,
                            onRetourAccueil: cc.retourAccueilIvr,
                          ),
                        )
                      else
                        const Spacer(),
                      if (showIncoming)
                        _incomingActions(cc)
                      else if (showActive)
                        _activeActions(cc)
                      else
                        _roundBtn(
                          icon: Icons.close,
                          color: Colors.grey,
                          label: "Fermer",
                          onPressed: () => _popScreen(),
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              // Auto-vue locale (mode NON dynamique : groupe). En 1-1 vidéo, le
              // PiP est géré par _draggablePip ci-dessous.
              if (!useDynamic &&
                  isVideo &&
                  showActive &&
                  cc.localStream != null)
                Positioned(
                  top: 12,
                  right: 12,
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              // Lot 3 : cadre flottant (PiP) déplaçable, tap pour inverser.
              if (useDynamic && dynPip != null)
                _draggablePip(dynPip!, dynPipMirror),
            ],
          ),
        ),
      ),
    );
  }

  /// Dégradés sombres haut/bas : lisibilité du nom, du minuteur et des contrôles
  /// par-dessus la vidéo. S'estompe avec les contrôles.
  Widget _scrims(bool visible) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cadre flottant (Picture-in-Picture) : déplaçable au doigt (aimanté au coin
  /// le plus proche au relâchement), tap pour permuter principal/secondaire.
  Widget _draggablePip(RTCVideoRenderer renderer, bool mirror) {
    const pipW = 112.0, pipH = 160.0, margin = 12.0;
    const topAnchor = 56.0;
    final size = MediaQuery.of(context).size;
    _pipPos ??= Offset(size.width - pipW - margin, topAnchor);
    final pos = _pipPos!;
    return AnimatedPositioned(
      duration: Duration(milliseconds: _pipDragging ? 0 : 250),
      curve: Curves.easeOut,
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => setState(() => _localIsMain = !_localIsMain),
        onPanStart: (_) => setState(() => _pipDragging = true),
        onPanUpdate: (d) {
          setState(() {
            final cur = _pipPos!;
            final nx = (cur.dx + d.delta.dx)
                .clamp(margin, size.width - pipW - margin)
                .toDouble();
            final ny = (cur.dy + d.delta.dy)
                .clamp(40.0, size.height - pipH - margin)
                .toDouble();
            _pipPos = Offset(nx, ny);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _pipDragging = false;
            // Aimante au coin le plus proche (animé par AnimatedPositioned).
            final cur = _pipPos!;
            final toLeft = cur.dx < (size.width - pipW) / 2;
            final toTop = cur.dy < (size.height - pipH) / 2;
            _pipPos = Offset(
              toLeft ? margin : size.width - pipW - margin,
              toTop ? topAnchor : size.height - pipH - margin,
            );
          });
        },
        child: Container(
          width: pipW,
          height: pipH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white30, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: RTCVideoView(
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }

  Widget _remoteGrid(CallController cc, Map<String, MediaStream> remotes,
      {required bool anonymiseLesInvites}) {
    final ids = remotes.keys.toList();
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 160),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ids.length <= 1 ? 1 : 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: ids.length,
          itemBuilder: (_, i) {
            final id = ids[i];
            final r = _remoteRenderers[id];
            final invited = cc.invitedParticipantIds.contains(id);
            // Même règle que pour le titre de l'écran, et seulement dans le même
            // cas : un tête-à-tête où un tiers a été amené par le correspondant.
            // Dans un VRAI groupe, savoir qui a rejoint reste utile — on ne
            // masque donc rien.
            final label = anonymiseLesInvites && invited
                ? "Invité"
                : (cc.participantNames[id] ?? "Participant");
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (r != null)
                    RTCVideoView(
                      r,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    const ColoredBox(color: AlanyaColors.gold),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: invited
                            ? AlanyaColors.forest.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        // « Invité (invité) » quand le nom est déjà masqué :
                        // le libellé anonyme se suffit à lui-même.
                        invited && label != "Invité"
                            ? "$label (invité)"
                            : label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Badge « invité » mis en évidence, affiché sous le nom quand l'interlocuteur
  /// actif est une personne invitée (ex. après un transfert supervisé).
  Widget _invitedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AlanyaColors.forest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AlanyaColors.forest.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 15),
          SizedBox(width: 6),
          Text(
            "Invité",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Rangée LISIBLE des invités présents (remplace l'ancienne liste blanc sur
  /// blanc). Chaque invité : pastille accentuée, icône + « Nom (invité) ».
  Widget _invitedChips(CallController cc, List<String> ids) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: ids.map((id) {
          final label = cc.participantNames[id] ?? "Invité";
          final connected = cc.remoteStreams.containsKey(id);
          return Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
            decoration: BoxDecoration(
              color: AlanyaColors.forest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  child: Text(
                    label.isNotEmpty ? label[0].toUpperCase() : "?",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  "$label (invité)",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (!connected) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _incomingActions(CallController cc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          icon: Icons.call_end,
          color: Colors.red,
          label: "Refuser",
          onPressed: () => _reject(cc),
        ),
        _roundBtn(
          icon: Icons.call,
          color: AlanyaColors.forest,
          label: "Accepter",
          onPressed: () => _accept(cc),
        ),
      ],
    );
  }

  Widget _activeActions(CallController cc) {
    if (cc.activeRole == ActiveCallRole.outgoing) {
      /*
       * STANDARD : MICRO ET HAUT-PARLEUR, malgré un appel encore « sortant ».
       *
       * Demande du user, 12/08/2026. L'état est bien `outgoing` tant qu'aucun
       * agent n'a décroché, mais la situation n'a rien d'un appel qui sonne dans
       * le vide : l'appelant ÉCOUTE déjà — invite vocale puis musique d'attente —
       * et son micro est ouvert depuis `startOutgoing`, qui construit la mesh
       * d'emblée pour être prêt au décrochage. Les deux commandes agissent donc
       * réellement, et le haut-parleur est justement ce qu'on cherche quand on
       * écoute un menu en tenant son téléphone à la main.
       *
       * Les autres commandes restent absentes, et c'est volontaire : inviter,
       * transférer ou envoyer un message n'a pas de sens tant qu'il n'y a
       * personne en face.
       */
      if (cc.ivr != null) {
        /*
         * 🔴 UNE SEULE RANGÉE : micro — raccrocher — haut-parleur.
         *
         * Demande du user (17/08/2026), après constat sur device : les deux
         * commandes étaient EMPILÉES au-dessus du bouton rouge, et cette
         * colonne de trois étages recouvrait le texte du panneau.
         *
         * Le gain n'est pas cosmétique : la hauteur des commandes passe
         * d'environ 190 points (56 + libellé + écart + 72 + libellé) à 90, et
         * tout ce qui est repris ici revient au pavé numérique. C'est aussi la
         * disposition d'un téléphone — l'action destructrice au centre, les
         * bascules de part et d'autre, à égale distance du pouce.
         */
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _controlBtn(
              icon: cc.isMuted ? Icons.mic_off : Icons.mic,
              active: cc.isMuted,
              label: cc.isMuted ? "Muet" : "Micro",
              onPressed: cc.toggleMute,
              taille: 52,
            ),
            const SizedBox(width: 22),
            _roundBtn(
              icon: Icons.call_end,
              color: Colors.red,
              label: "Raccrocher",
              onPressed: () => _hangUp(cc),
              taille: 64,
            ),
            const SizedBox(width: 22),
            _controlBtn(
              icon: cc.isSpeakerOn ? Icons.volume_up : Icons.hearing,
              active: cc.isSpeakerOn,
              label: "Haut-parleur",
              onPressed: () => cc.toggleSpeaker(),
              taille: 52,
            ),
          ],
        );
      }
      // Appel sortant ordinaire : uniquement le bouton rouge Raccrocher
      // (« Annuler » supprimé — il faisait doublon).
      return _roundBtn(
        icon: Icons.call_end,
        color: Colors.red,
        label: "Raccrocher",
        onPressed: () => _hangUp(cc),
      );
    }
    // Appel actif (en connexion ou connecté) : barre de contrôles + raccrocher.
    final isVideo = _estVideo(cc);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 12,
          children: [
            _controlBtn(
              icon: cc.isMuted ? Icons.mic_off : Icons.mic,
              active: cc.isMuted,
              label: cc.isMuted ? "Muet" : "Micro",
              onPressed: cc.toggleMute,
            ),
            _controlBtn(
              icon: cc.isSpeakerOn ? Icons.volume_up : Icons.hearing,
              active: cc.isSpeakerOn,
              label: "Haut-parleur",
              onPressed: () => cc.toggleSpeaker(),
            ),
            if (isVideo)
              _controlBtn(
                icon: cc.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                active: !cc.isVideoEnabled,
                label: "Vidéo",
                onPressed: cc.toggleVideo,
              ),
            if (isVideo)
              _controlBtn(
                icon: Icons.cameraswitch,
                active: false,
                label: "Caméra",
                onPressed: () => cc.switchCamera(),
              ),
            _controlBtn(
              icon: Icons.chat_bubble_outline,
              active: false,
              label: "Message",
              onPressed: () => _openChatDuringCall(cc),
            ),
            _controlBtn(
              icon: Icons.person_add_alt_1,
              active: false,
              label: "Inviter",
              onPressed: () => _invite(cc),
            ),
            _controlBtn(
              icon: cc.isTransferring ? Icons.close : Icons.phone_forwarded,
              active: cc.isTransferring,
              label: cc.isTransferring ? "Annuler" : "Transférer",
              onPressed: cc.isTransferring
                  ? () {
                      cc.cancelTransfer(reason: "Transfert annulé");
                      showAppSnackBar("Transfert annulé");
                    }
                  : () => _transfer(cc),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _roundBtn(
          icon: Icons.call_end,
          color: Colors.red,
          label:
              cc.isGroupCall && !cc.isCallInitiator ? "Quitter" : "Raccrocher",
          onPressed: () => _hangUp(cc),
        ),
      ],
    );
  }

  /// Invite un ou plusieurs contacts dans l'appel (appel de groupe dynamique).
  /// L'appelant reste dans l'appel ; chaque invité rejoint quand il décroche.
  Future<void> _invite(CallController cc) async {
    final numbers = await ContactPickerSheet.show(
      context,
      title: "Inviter dans l'appel",
      confirmLabel: "Inviter",
    );
    if (numbers == null || numbers.isEmpty || !mounted) return;
    for (final n in numbers) {
      cc.inviteToCall(n);
    }
    showAppSnackBar(numbers.length == 1
        ? "Invitation envoyée"
        : "${numbers.length} invitations envoyées");
  }

  /// Transfert supervisé : choisit un contact, l'invite dans l'appel, puis
  /// l'appelant quittera automatiquement quand l'invité décroche.
  Future<void> _transfer(CallController cc) async {
    final numbers = await ContactPickerSheet.show(
      context,
      title: "Transférer l'appel à…",
      confirmLabel: "Transférer",
    );
    if (numbers == null || numbers.isEmpty || !mounted) return;
    cc.transferCall(numbers.first);
    showAppSnackBar(
        "Transfert en cours… l'appel basculera quand le contact décroche.");
  }

  /// Ouvre la conversation pendant l'appel : minimise l'écran d'appel (le
  /// bandeau global prend le relais) puis pousse le chat. L'appel continue
  /// (le CallController est global, le média n'est pas coupé).
  void _openChatDuringCall(CallController cc) {
    final convId = cc.activeConvId;
    if (convId == null) {
      showAppSnackBar("Conversation indisponible");
      return;
    }
    final title =
        cc.activePeerName ?? cc.incoming?.displayTitle ?? "Conversation";
    final isGroup = cc.isGroupCall;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(convId: convId, title: title, isGroup: isGroup),
      ),
    );
  }

  /// Petit bouton de contrôle en overlay (semi-transparent) : allumé = teinté.
  /// [taille] permet de resserrer les commandes là où la place est comptée —
  /// la rangée du standard, où chaque point repris revient au pavé numérique.
  /// Les autres écrans gardent la taille d'origine par défaut.
  Widget _controlBtn({
    required IconData icon,
    required bool active,
    required String label,
    required VoidCallback onPressed,
    double taille = 56,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? Colors.white : Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: taille,
              height: taille,
              child: Icon(icon,
                  color: active ? AlanyaColors.chocolate : Colors.white,
                  size: taille * 0.46),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
    double taille = 72,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: taille,
              height: taille,
              child: Icon(icon, color: Colors.white, size: taille * 0.44),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
