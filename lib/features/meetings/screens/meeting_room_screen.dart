import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../auth/auth_controller.dart';
import '../meeting_controller.dart';

/// Écran de réunion active — style Google Meet.
///
/// Affiche les flux vidéo/audio des participants, avec des contrôles pour
/// micro, caméra, haut-parleur et quitter. Le [MeetingController] est GLOBAL :
/// fermer cet écran (flèche de réduction ou retour système) ne quitte pas la
/// réunion, il la minimise — le bandeau global permet d'y revenir, et le
/// service de premier plan garde l'audio vivant en arrière-plan.
class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({
    super.key,
    required this.meetingId,
    required this.objet,
    required this.isVideo,
  });

  final int meetingId;
  final String objet;
  final bool isVideo;

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  bool _joining = true;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    final ctrl = context.read<MeetingController>();
    // Ne rejoint que si on n'est pas déjà dans cette réunion (réouverture via
    // le bandeau) : le flux et la maille sont déjà en place.
    if (ctrl.activeMeetingId == widget.meetingId && ctrl.isActive) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    try {
      await ctrl.join(
        widget.meetingId,
        isVideo: widget.isVideo,
        objet: widget.objet,
      );
      if (mounted) setState(() => _joining = false);
    } catch (e) {
      // Permission refusée ou autre échec : on ne reste pas planté sur un
      // écran d'erreur sans recours. On affiche un message et on revient, car
      // la réunion n'a pas démarré localement.
      if (mounted) {
        final msg = e
            .toString()
            .replaceFirst("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La salle est affichée → masque le bandeau global. Posé en post-frame car
    // il peut être appelé plusieurs fois au fil des dépendances.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MeetingController>().setRoomVisible(true);
    });
  }

  /// Réduit la salle SANS quitter : la réunion continue, le bandeau prend le
  /// relais. C'est le geste de retour système comme du bouton dédié.
  void _minimize() {
    Navigator.of(context).maybePop();
  }

  Future<void> _leave() async {
    final ctrl = context.read<MeetingController>();
    await ctrl.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // L'écran disparaît : le bandeau global reprend si la réunion continue.
    // On ne quitte PAS la réunion ici — c'est le rôle du bouton rouge.
    context.read<MeetingController>().setRoomVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      // Le retour système RÉDUIT la réunion, il ne la quitte pas : l'audio doit
      // continuer. Pour raccrocher, le bouton rouge reste le geste explicite.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          context.read<MeetingController>().setRoomVisible(false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: _joining
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Connexion en cours...",
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              : Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildVideoGrid()),
                        _buildControls(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            tooltip: "Réduire",
            onPressed: _minimize,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.objet,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ListenableBuilder(
                  listenable: context.read<MeetingController>(),
                  builder: (_, __) {
                    final ctrl = context.read<MeetingController>();
                    return Text(
                      _subtitle(ctrl),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    );
                  },
                ),
              ],
            ),
          ),
          // Bouton participants
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.white),
            onPressed: _showParticipants,
          ),
        ],
      ),
    );
  }

  /// Sous-titre d'en-tête : minuteur de participation une fois le flux local
  /// prêt, sinon nombre de participants. Le compteur retenu est
  /// [MeetingController.participantCount] (participants annoncés par le
  /// serveur), pas le nombre de flux média connectés — un nouveau venu doit
  /// être compté tout de suite, pas seulement après sa négociation WebRTC.
  String _subtitle(MeetingController ctrl) {
    final depuis = ctrl.connectedSince;
    final compte = ctrl.participantCount;
    if (depuis != null) {
      final d = DateTime.now().difference(depuis);
      String two(int n) => n.toString().padLeft(2, '0');
      final t = d.inHours > 0
          ? "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}"
          : "${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
      return "$compte · $t";
    }
    return "$compte participant(s)";
  }

  /// Zone centrale : vignettes des participants.
  ///
  /// En RÉUNION AUDIO, on n'instancie AUCUN [RTCVideoRenderer] : le flux local
  /// ne contient qu'une piste audio, et créer des renderers vidéo réveillait la
  /// caméra sur certaines implémentations. On affiche à la place une liste
  /// d'avatars (le même style que la fiche participants). En vidéo, on rend les
  /// flux comme avant.
  Widget _buildVideoGrid() {
    return ListenableBuilder(
      listenable: context.read<MeetingController>(),
      builder: (_, __) {
        final ctrl = context.read<MeetingController>();

        if (!ctrl.activeIsVideo) {
          return _buildAudioGrid(ctrl);
        }

        final remoteIds = ctrl.remoteStreams.keys.toList();
        final remoteCount = remoteIds.length;
        // Participants logiques (y compris ceux dont le flux n'est pas encore
        // négocié) : on leur réserve une case avec un avatar en attendant.
        final logicalOthers = ctrl.participantNames.keys.toList();
        // Ceux qui n'ont pas encore de flux : affichés en avatar.
        final pending = logicalOthers
            .where((id) => !ctrl.remoteStreams.containsKey(id))
            .toList();
        final total = 1 + remoteCount + pending.length;

        if (total <= 1) {
          // Seul dans la réunion
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _localVideo(isLarge: true),
                const SizedBox(height: 16),
                const Text("En attente d'autres participants...",
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        if (total == 2 && remoteCount == 1) {
          // 1v1 : local en petit coin, remote en grand
          return Stack(
            children: [
              Positioned.fill(child: _remoteVideoSingle()),
              Positioned(
                right: 16,
                top: 16,
                width: 120,
                height: 160,
                child: _localVideo(isLarge: false),
              ),
            ],
          );
        }

        // Grille. Les tuiles sont ordonnées : soi, les flux distants, puis les
        // participants en attente de média (avatar).
        final cols = total <= 4 ? 2 : 3;
        final rows = (total / cols).ceil();
        final tiles = <Widget>[
          _localVideo(isLarge: false),
          ...remoteIds.map(_remoteVideoTile),
          ...pending.map((id) => _remoteVideoTile(id)),
        ];
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: rows == 1 ? 1.5 : 1.0,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) => tiles[i],
        );
      },
    );
  }

  /// Grille affichée en réunion AUDIO : avatars uniquement, pas de renderer.
  Widget _buildAudioGrid(MeetingController ctrl) {
    final me = context.read<AuthController>().user;
    // Moi + participants annoncés.
    final entries = <({String id, String name, String? avatar, bool muted, bool me})>[
      (
        id: "me",
        name: me?.pseudo ?? "Vous",
        avatar: me?.avatarUrl,
        muted: ctrl.isMuted,
        me: true,
      ),
      for (final id in ctrl.participantNames.keys)
        (
          id: id,
          name: ctrl.participantNames[id] ?? "Participant",
          avatar: ctrl.participantAvatars[id],
          muted: ctrl.isPeerMuted(id),
          me: false,
        ),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 28,
          runSpacing: 28,
          alignment: WrapAlignment.center,
          children: entries.map((e) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarCircle(
                      name: e.name,
                      avatarUrl: e.avatar,
                      radius: 44,
                      backgroundColor: e.me
                          ? AlanyaColors.terracotta
                          : AlanyaColors.forest,
                    ),
                    if (e.muted)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mic_off,
                              color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 96,
                  child: Text(
                    e.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _localVideo({required bool isLarge}) {
    final ctrl = context.watch<MeetingController>();
    final stream = ctrl.localStream;
    if (stream == null || ctrl.isCameraOff) {
      return _avatarPlaceholder(
        name: context.read<AuthController>().user?.pseudo ?? "Moi",
        isLarge: isLarge,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
      child: RTCVideoRendererObject(stream: stream),
    );
  }

  Widget _remoteVideoSingle() {
    final ctrl = context.watch<MeetingController>();
    final streams = ctrl.remoteStreams;
    if (streams.isEmpty) return const SizedBox.shrink();
    final entry = streams.entries.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: RTCVideoRendererObject(stream: entry.value),
    );
  }

  Widget _remoteVideoTile(String peerId) {
    final ctrl = context.watch<MeetingController>();
    final stream = ctrl.remoteStreams[peerId];
    final name = ctrl.participantNames[peerId] ?? "Participant";
    final avatarUrl = ctrl.participantAvatars[peerId];
    final muted = ctrl.isPeerMuted(peerId);
    final hasVideo = stream != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            RTCVideoRendererObject(stream: stream)
          else
            _avatarPlaceholder(
                name: name, isLarge: false, avatarUrl: avatarUrl),
          // Bandeau nom + état muet
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                if (muted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off,
                        color: Colors.white, size: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder({
    required String name,
    required bool isLarge,
    String? avatarUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
      ),
      child: Center(
        child: AvatarCircle(
          name: name,
          avatarUrl: avatarUrl,
          radius: isLarge ? 40 : 24,
          backgroundColor: AlanyaColors.terracotta.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return ListenableBuilder(
      listenable: context.read<MeetingController>(),
      builder: (_, __) {
        final ctrl = context.read<MeetingController>();
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 16,
            runSpacing: 12,
            children: [
              // Micro
              _controlButton(
                icon: ctrl.isMuted ? Icons.mic_off : Icons.mic,
                label: ctrl.isMuted ? "Activer" : "Muet",
                isActive: !ctrl.isMuted,
                onTap: ctrl.toggleMute,
              ),
              // Caméra (vidéo uniquement)
              if (ctrl.activeIsVideo)
                _controlButton(
                  icon: ctrl.isCameraOff
                      ? Icons.videocam_off
                      : Icons.videocam,
                  label: ctrl.isCameraOff ? "Caméra off" : "Caméra",
                  isActive: !ctrl.isCameraOff,
                  onTap: ctrl.toggleCamera,
                ),
              // Bascule caméra avant/arrière (vidéo uniquement)
              if (ctrl.activeIsVideo)
                _controlButton(
                  icon: Icons.cameraswitch,
                  label: "Retourner",
                  isActive: false,
                  onTap: () => ctrl.switchCamera(),
                ),
              // Haut-parleur
              _controlButton(
                icon:
                    ctrl.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                label: "Haut-parleur",
                isActive: ctrl.isSpeakerOn,
                onTap: () => ctrl.toggleSpeaker(),
              ),
              // Quitter
              _controlButton(
                icon: Icons.call_end,
                label: "Quitter",
                isActive: false,
                isLeave: true,
                onTap: _leave,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isLeave = false,
  }) {
    final bgColor = isLeave
        ? Colors.red
        : isActive
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08);
    final iconColor = isLeave
        ? Colors.white
        : isActive
            ? Colors.white
            : Colors.white54;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  void _showParticipants() {
    final me = context.read<AuthController>().user;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: context.read<MeetingController>(),
          builder: (_, __) {
            final ctrl = context.read<MeetingController>();
            final peerIds = ctrl.participantNames.keys.toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text("Participants",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Text("${ctrl.participantCount}",
                            style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Moi
                        ListTile(
                          leading: AvatarCircle(
                            name: me?.pseudo ?? "Moi",
                            avatarUrl: me?.avatarUrl,
                            radius: 18,
                            backgroundColor: AlanyaColors.terracotta,
                          ),
                          title: Text(
                              me?.pseudo ?? "Vous",
                              style: const TextStyle(color: Colors.white)),
                          trailing: Icon(
                            ctrl.isMuted ? Icons.mic_off : Icons.mic,
                            color:
                                ctrl.isMuted ? Colors.red : Colors.white54,
                            size: 20,
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        // Autres
                        ...peerIds.map((peerId) {
                          final name =
                              ctrl.participantNames[peerId] ?? "Participant";
                          final avatar =
                              ctrl.participantAvatars[peerId];
                          final muted = ctrl.isPeerMuted(peerId);
                          return ListTile(
                            leading: AvatarCircle(
                              name: name,
                              avatarUrl: avatar,
                              radius: 18,
                              backgroundColor: AlanyaColors.forest,
                            ),
                            title: Text(name,
                                style:
                                    const TextStyle(color: Colors.white)),
                            trailing: Icon(
                              muted ? Icons.mic_off : Icons.mic,
                              color: muted ? Colors.red : Colors.white54,
                              size: 20,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Wrapper simple pour afficher un flux WebRTC.
class RTCVideoRendererObject extends StatefulWidget {
  const RTCVideoRendererObject({super.key, required this.stream});
  final MediaStream stream;

  @override
  State<RTCVideoRendererObject> createState() => _RTCVideoRendererObjectState();
}

class _RTCVideoRendererObjectState extends State<RTCVideoRendererObject> {
  final _renderer = RTCVideoRenderer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _renderer.srcObject = widget.stream;
    await _renderer.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return RTCVideoView(_renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }
}
