import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../auth/auth_controller.dart';
import '../meeting_controller.dart';
import '../meetings_repository.dart';

/// Écran de réunion active — style Google Meet.
///
/// Affiche les flux vidéo/audio des participants, avec des contrôles
/// pour micro, caméra, haut-parleur et quitter.
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
  late MeetingController _ctrl;
  bool _joining = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = MeetingController(
      context.read<MeetingsRepository>(),
      context.read(),
    );
    final user = context.read<AuthController>().user;
    if (user != null) {
      _ctrl.bindUser(user.id, user.pseudo ?? user.publicNumber);
    }
    _join();
  }

  Future<void> _join() async {
    try {
      await _ctrl.join(widget.meetingId, isVideo: widget.isVideo);
      setState(() => _joining = false);
    } catch (e) {
      setState(() {
        _joining = false;
        _error = "Impossible de rejoindre : $e";
      });
    }
  }

  @override
  void dispose() {
    _ctrl.leave();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Retour"),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // --- En-tête ---
                      _buildHeader(),
                      // --- Grille vidéo ---
                      Expanded(child: _buildVideoGrid()),
                      // --- Contrôles ---
                      _buildControls(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              _ctrl.leave();
              Navigator.pop(context);
            },
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
                  listenable: _ctrl,
                  builder: (_, __) => Text(
                    "${_ctrl.connectedPeerCount + 1} participant(s)",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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

  Widget _buildVideoGrid() {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (_, __) {
        final remoteCount = _ctrl.remoteStreams.length;
        final total = remoteCount + 1; // +1 pour le local

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

        if (total == 2) {
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

        // Grille pour 3+ participants
        final cols = total <= 4 ? 2 : 3;
        final rows = (total / cols).ceil();
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: rows == 1 ? 1.5 : 1.0,
          ),
          itemCount: total,
          itemBuilder: (_, i) {
            if (i == 0) return _localVideo(isLarge: false);
            final peerId = _ctrl.remoteStreams.keys.elementAt(i - 1);
            return _remoteVideoTile(peerId);
          },
        );
      },
    );
  }

  Widget _localVideo({required bool isLarge}) {
    final stream = _ctrl.localStream;
    if (stream == null || _ctrl.isCameraOff) {
      return _avatarPlaceholder(
        name: context.read<AuthController>().user?.pseudo ?? "Moi",
        isLarge: isLarge,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
      child: RTCVideoRendererObject(stream: stream).build(),
    );
  }

  Widget _remoteVideoSingle() {
    final streams = _ctrl.remoteStreams;
    if (streams.isEmpty) return const SizedBox.shrink();
    final entry = streams.entries.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: RTCVideoRendererObject(stream: entry.value).build(),
    );
  }

  Widget _remoteVideoTile(String peerId) {
    final stream = _ctrl.remoteStreams[peerId];
    final name = _ctrl.participantNames[peerId] ?? "Participant";
    if (stream == null) {
      return _avatarPlaceholder(name: name, isLarge: false);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: RTCVideoRendererObject(stream: stream).build(),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder({required String name, required bool isLarge}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
      ),
      child: Center(
        child: AvatarCircle(
          name: name,
          avatarUrl: null,
          radius: isLarge ? 40 : 24,
          backgroundColor: AlanyaColors.terracotta.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Micro
              _controlButton(
                icon: _ctrl.isMuted ? Icons.mic_off : Icons.mic,
                label: _ctrl.isMuted ? "Activer" : "Muet",
                isActive: !_ctrl.isMuted,
                onTap: _ctrl.toggleMute,
              ),
              // Caméra
              _controlButton(
                icon: _ctrl.isCameraOff ? Icons.videocam_off : Icons.videocam,
                label: _ctrl.isCameraOff ? "Caméra" : "Caméra",
                isActive: !_ctrl.isCameraOff,
                onTap: _ctrl.toggleCamera,
              ),
              // Haut-parleur
              _controlButton(
                icon: _ctrl.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                label: "Haut-parleur",
                isActive: _ctrl.isSpeakerOn,
                onTap: _ctrl.toggleSpeaker,
              ),
              // Quitter
              _controlButton(
                icon: Icons.call_end,
                label: "Quitter",
                isActive: false,
                isLeave: true,
                onTap: () {
                  _ctrl.leave();
                  Navigator.pop(context);
                },
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: _ctrl,
          builder: (_, __) {
            final peers = _ctrl.remoteStreams.keys.toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("Participants",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  // Moi
                  ListTile(
                    leading: AvatarCircle(
                      name: context.read<AuthController>().user?.pseudo ?? "Moi",
                      avatarUrl: null,
                      radius: 18,
                      backgroundColor: AlanyaColors.terracotta,
                    ),
                    title: const Text("Vous",
                        style: TextStyle(color: Colors.white)),
                    trailing: Icon(
                      _ctrl.isMuted ? Icons.mic_off : Icons.mic,
                      color: _ctrl.isMuted ? Colors.red : Colors.white54,
                      size: 20,
                    ),
                  ),
                  // Autres
                  ...peers.map((peerId) {
                    final name = _ctrl.participantNames[peerId] ?? "Participant";
                    return ListTile(
                      leading: AvatarCircle(
                        name: name,
                        avatarUrl: null,
                        radius: 18,
                        backgroundColor: AlanyaColors.forest,
                      ),
                      title:
                          Text(name, style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.mic,
                          color: Colors.white54, size: 20),
                    );
                  }),
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
    return RTCVideo(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }
}
