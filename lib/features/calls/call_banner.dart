import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/push_service.dart';
import '../../theme/alanya_theme.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// Bandeau global « appel en cours » (style WhatsApp) affiché au-dessus de
/// toutes les pages quand un appel est actif MAIS que l'écran plein-écran
/// d'appel n'est pas affiché (ex: l'utilisateur a ouvert une conversation via
/// le bouton « Message » pendant l'appel). Toucher le bandeau rouvre l'appel.
///
/// À utiliser dans `MaterialApp.builder`, à l'intérieur d'un Stack.
class CallBanner extends StatefulWidget {
  const CallBanner({super.key});

  @override
  State<CallBanner> createState() => _CallBannerState();
}

class _CallBannerState extends State<CallBanner> {
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
    final cc = context.watch<CallController>();
    final visible = cc.activeRole != null && !cc.callScreenVisible;
    if (!visible) return const SizedBox.shrink();

    // Le libellé suit la PHASE réelle de l'appel.
    //
    // ⚠️ Il annonçait « Appel en cours » dès qu'un appel existait, y compris
    // pendant la sonnerie : l'appelant lisait donc que la communication était
    // établie alors que personne n'avait décroché, et se demandait pourquoi il
    // n'entendait rien. `connectedSince` n'est renseigné qu'au premier flux
    // média reçu — c'est le seul critère fiable pour dire « en cours ».
    final elapsed = _elapsed(cc.connectedSince);
    final String label;
    if (elapsed.isNotEmpty) {
      label = "Appel en cours · $elapsed";
    } else if (cc.activeRole == ActiveCallRole.outgoing) {
      label = "Appel en cours d'établissement…";
    } else if (cc.incoming != null) {
      label = "Appel entrant…";
    } else {
      label = "Connexion…";
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              PushService.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const ActiveCallScreen(incoming: false),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AlanyaColors.terracotta,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.call, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text("Revenir", style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
