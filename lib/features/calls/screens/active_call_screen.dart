import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../chat/screens/chat_screen.dart';
import '../call_controller.dart';
import '../widgets/call_avatar_waves.dart';

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
      _popScreen();
    }
    if (mounted) _syncStreams();
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

  void _popScreen() {
    if (_popping || !mounted) return;
    _popping = true;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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

  String _formatElapsed() {
    final m = _elapsed ~/ 60;
    final s = _elapsed % 60;
    return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
  }

  String _statusText(CallController cc) {
    if (widget.incoming && cc.incoming != null) {
      final inc = cc.incoming!;
      if (inc.isGroup) return "Groupe · ${inc.memberCount} membres";
      return "Appel entrant…";
    }
    if (cc.activeRole == ActiveCallRole.outgoing) {
      if (cc.isGroupCall) return "Sonnerie du groupe…";
      return cc.remoteRinging ? "En train de sonner…" : "Sonnerie…";
    }
    if (cc.activeRole == ActiveCallRole.ongoing) {
      if (cc.mediaConnected) return _formatElapsed();
      return "Connexion en cours…";
    }
    return "Connexion en cours…";
  }

  String _mediaHint(CallController cc) {
    if (cc.activeRole != ActiveCallRole.ongoing) return "";
    if (cc.isGroupCall) {
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
    final bool primaryInvited =
        primaryId != null && cc.invitedParticipantIds.contains(primaryId);
    // Pastilles « invité » à afficher séparément (invités qui ne sont pas déjà
    // l'interlocuteur principal mis en évidence).
    final invitedChipIds =
        invitedOthers.where((id) => id != primaryId).toList();

    final String name = widget.incoming
        ? (cc.incoming?.displayTitle ?? "Appel")
        : (primaryId != null
            ? (cc.participantNames[primaryId] ?? cc.activePeerName ?? "Contact")
            : (cc.activePeerName ?? "Contact"));
    // Après acceptation d'un appel entrant, cc.incoming repasse à null alors que
    // widget.incoming reste true : l'ancien code lisait donc cc.incoming?.callType
    // == null → isVideo=false → l'UI masquait la vidéo (distante ET auto-vue) même
    // pour un appel vidéo. On lit incoming.callType pendant la sonnerie, puis on
    // retombe sur activeType une fois l'appel actif.
    final isVideo = (cc.incoming?.callType ?? cc.activeType) == "VIDEO";
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
        if (showIncoming) {
          await _reject(cc);
        } else if (showActive) {
          await _hangUp(cc);
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
                _remoteGrid(cc, remotes),
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          tooltip: "Fermer",
                          onPressed: () async {
                            if (showIncoming) {
                              await _reject(cc);
                            } else if (showActive) {
                              await _hangUp(cc);
                            } else {
                              _popScreen();
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!showVideo && !useDynamic)
                        CallAvatarWaves(
                          diameter: 104,
                          color: AlanyaColors.forest,
                          active: cc.activeRole == ActiveCallRole.ongoing ||
                              cc.activeRole == ActiveCallRole.outgoing,
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: AlanyaColors.terracotta,
                            child: cc.isGroupCall
                                ? const Icon(Icons.groups,
                                    size: 48, color: Colors.white)
                                : Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : "?",
                                    style: const TextStyle(
                                      fontSize: 44,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      if (!showVideo) const SizedBox(height: 20),
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
                      const SizedBox(height: 8),
                      Text(_statusText(cc),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16)),
                      if (cc.activeRole == ActiveCallRole.ongoing) ...[
                        const SizedBox(height: 10),
                        Text(_mediaHint(cc),
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

  Widget _remoteGrid(CallController cc, Map<String, MediaStream> remotes) {
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
            final label = cc.participantNames[id] ?? "Participant";
            final invited = cc.invitedParticipantIds.contains(id);
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
                        invited ? "$label (invité)" : label,
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
      // Appel sortant : uniquement le bouton rouge Raccrocher (« Annuler »
      // supprimé — il faisait doublon).
      return _roundBtn(
        icon: Icons.call_end,
        color: Colors.red,
        label: "Raccrocher",
        onPressed: () => _hangUp(cc),
      );
    }
    // Appel actif (en connexion ou connecté) : barre de contrôles + raccrocher.
    final isVideo = (cc.incoming?.callType ?? cc.activeType) == "VIDEO";
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
              icon: Icons.phone_forwarded,
              active: cc.isTransferring,
              label: cc.isTransferring ? "Transfert…" : "Transférer",
              onPressed: cc.isTransferring ? () {} : () => _transfer(cc),
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
  Widget _controlBtn({
    required IconData icon,
    required bool active,
    required String label,
    required VoidCallback onPressed,
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
              width: 56,
              height: 56,
              child: Icon(icon,
                  color: active ? AlanyaColors.chocolate : Colors.white,
                  size: 26),
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
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
