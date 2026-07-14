import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../theme/app_theme.dart';
import '../call_controller.dart';

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

  Timer? _connectTimeout;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final cc = _calls;
      if (cc != null && cc.activeRole == ActiveCallRole.ongoing) {
        setState(() => _elapsed++);
      }
    });
    // Timeout : si la connexion WebRTC n'est pas établie après 30s, raccroche
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      final cc = _calls;
      if (cc != null && cc.activeRole == ActiveCallRole.ongoing && !cc.mediaConnected) {
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
    final stale = _remoteRenderers.keys.where((k) => !remotes.containsKey(k)).toList();
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

  Future<void> _closeOutgoing(CallController cc) async {
    if (cc.activeRole == ActiveCallRole.outgoing) {
      await _hangUp(cc);
      return;
    }
    _popScreen();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectTimeout?.cancel();
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
      return cc.isGroupCall ? "Sonnerie du groupe…" : "Sonnerie…";
    }
    if (cc.activeRole == ActiveCallRole.ongoing) {
      if (cc.mediaConnected) return _formatElapsed();
      return "Connexion…";
    }
    return "Connexion…";
  }

  String _mediaHint(CallController cc) {
    if (cc.activeRole != ActiveCallRole.ongoing) return "";
    if (cc.isGroupCall) {
      return "${cc.connectedPeerCount} connecté(s) · ${cc.joinedParticipantIds.length} dans l'appel";
    }
    if (cc.mediaConnected) {
      return cc.activeType == "VIDEO" ? "Vidéo connectée" : "Audio connectée";
    }
    return "Établissement du lien WebRTC…";
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.watch<CallController>();
    final name = widget.incoming
        ? (cc.incoming?.displayTitle ?? "Appel")
        : (cc.activePeerName ?? "Contact");
    final isVideo = (widget.incoming ? cc.incoming?.callType : cc.activeType) == "VIDEO";
    final remotes = cc.remoteStreams;
    final showVideo = isVideo && cc.activeRole == ActiveCallRole.ongoing && remotes.isNotEmpty;
    final showIncoming = widget.incoming && cc.incoming != null;
    final showActive = cc.activeCallId != null && cc.activeRole != null;

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
        backgroundColor: AppColors.chocolate,
        body: SafeArea(
          child: Stack(
            children: [
              if (showVideo) _remoteGrid(cc, remotes),
              Column(
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
                  if (!showVideo)
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: AppColors.terracotta,
                      child: Icon(
                        cc.isGroupCall
                            ? Icons.groups
                            : (isVideo ? Icons.videocam : Icons.person),
                        size: 52,
                        color: Colors.white,
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
                  const SizedBox(height: 8),
                  Text(_statusText(cc), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (cc.activeRole == ActiveCallRole.ongoing) ...[
                    const SizedBox(height: 10),
                    Text(_mediaHint(cc), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                  if (cc.lastError != null) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        cc.lastError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ),
                  ],
                  if (cc.isGroupCall && cc.activeRole == ActiveCallRole.ongoing)
                    _participantList(cc),
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
              if (showVideo && cc.localStream != null)
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
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
            ],
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
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (r != null)
                    RTCVideoView(
                      r,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    const ColoredBox(color: AppColors.clay),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
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

  Widget _participantList(CallController cc) {
    final ids = cc.joinedParticipantIds.where((id) => id != cc.myUserId).toList();
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: ids.map((id) {
          final label = cc.participantNames[id] ?? "Membre";
          final connected = cc.remoteStreams.containsKey(id);
          return Chip(
            avatar: CircleAvatar(
              backgroundColor: connected ? AppColors.forest : AppColors.clay,
              child: Text(label.isNotEmpty ? label[0].toUpperCase() : "?",
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            label: Text(label, style: const TextStyle(color: Colors.white70)),
            backgroundColor: Colors.white12,
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
          color: AppColors.forest,
          label: "Accepter",
          onPressed: () => _accept(cc),
        ),
      ],
    );
  }

  Widget _activeActions(CallController cc) {
    if (cc.activeRole == ActiveCallRole.outgoing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundBtn(
            icon: Icons.close,
            color: Colors.grey.shade700,
            label: "Annuler",
            onPressed: () => _closeOutgoing(cc),
          ),
          _roundBtn(
            icon: Icons.call_end,
            color: Colors.red,
            label: "Raccrocher",
            onPressed: () => _hangUp(cc),
          ),
        ],
      );
    }
    return _roundBtn(
      icon: Icons.call_end,
      color: Colors.red,
      label: cc.isGroupCall && !cc.isCallInitiator ? "Quitter" : "Raccrocher",
      onPressed: () => _hangUp(cc),
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
