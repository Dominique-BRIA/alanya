import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:alanya/core/push_service.dart';
import 'package:alanya/theme/alanya_theme.dart';
import 'meeting_controller.dart';
import 'meeting_room_screen.dart';

/// Bandeau global « réunion en cours » affiché par-dessus toutes les pages
/// quand une réunion est active mais que l'écran de salle n'est pas affiché
/// (l'utilisateur l'a réduite pour naviguer dans l'app). Toucher le bandeau
/// rouvre la salle.
///
/// À utiliser dans `MaterialApp.builder`, à l'intérieur d'un Stack (aux côtés
/// du `CallBanner`).
class MeetingBanner extends StatefulWidget {
  const MeetingBanner({super.key});

  @override
  State<MeetingBanner> createState() => _MeetingBannerState();
}

class _MeetingBannerState extends State<MeetingBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Rafraîchit le minuteur chaque seconde tant que le bandeau vit.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime? since) {
    if (since == null) return "";
    final d = DateTime.now().difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    final base =
        "${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
    return d.inHours > 0 ? "${two(d.inHours)}:$base" : base;
  }

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<MeetingController>();
    final visible = mc.isActive && !mc.roomVisible;
    if (!visible) return const SizedBox.shrink();

    final elapsed = _elapsed(mc.connectedSince);
    final label = elapsed.isNotEmpty
        ? "Réunion en cours · $elapsed"
        : "Réunion en cours…";

    // Décalé sous le bandeau d'appel si jamais les deux coexistent (peu
    // probable, les réunions ne verrouillent pas l'état occupé).
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                final id = mc.activeMeetingId;
                if (id == null) return;
                PushService.navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => MeetingRoomScreen(
                      meetingId: id,
                      objet: mc.activeObjet ?? "Réunion",
                      isVideo: mc.activeIsVideo,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AlanyaColors.forest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black38),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Text("Revenir",
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
