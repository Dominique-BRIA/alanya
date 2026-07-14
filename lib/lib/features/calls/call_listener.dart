import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/debug_overlay.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// Écoute les appels entrants et ouvre l'écran d'appel automatiquement.
class CallListener extends StatefulWidget {
  const CallListener({super.key, required this.child});
  final Widget child;

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  bool _incomingRouteOpen = false;

  @override
  Widget build(BuildContext context) {
    final cc = context.watch<CallController>();
    final incId = cc.incoming?.callId;
    DebugOverlay.log("CL build(inc=${incId == null ? "-" : incId.substring(0, incId.length < 8 ? incId.length : 8)}, open=$_incomingRouteOpen)");
    if (cc.incoming != null) {
      debugPrint("[CallListener] cc.incoming n'est pas nul ! Ouverture de l'écran d'appel...");
    }
    if (cc.incoming != null && !_incomingRouteOpen) {
      DebugOverlay.log("CL 🚨 va push ActiveCallScreen");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || cc.incoming == null) {
          DebugOverlay.log("CL ❌ abandon (mnt=$mounted inc=${cc.incoming})");
          return;
        }
        setState(() => _incomingRouteOpen = true);
        DebugOverlay.log("CL → Navigator.push");
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ActiveCallScreen(incoming: true),
          ),
        );
        if (mounted) setState(() => _incomingRouteOpen = false);
      });
    }
    return widget.child;
  }
}
