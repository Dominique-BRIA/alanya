import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/debug_overlay.dart';
import '../../core/in_app_notifier.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// Écoute les appels entrants et, quand l'app est **ouverte** (premier plan),
/// affiche un heads-up in-app glassmorphism (Refuser / Répondre) au lieu
/// d'ouvrir directement l'écran plein.
///
/// * Répondre / tap → accepte puis ouvre l'écran d'appel.
/// * Refuser → rejette l'appel.
/// * Le heads-up disparaît dès que l'appel n'est plus « entrant » (accepté,
///   rejeté ou annulé par l'appelant).
///
/// (Quand l'app est fermée/en arrière-plan, c'est la notification système
/// plein écran — full-screen intent — qui prend le relais, gérée ailleurs.)
class CallListener extends StatefulWidget {
  const CallListener({super.key, required this.child});
  final Widget child;

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  String? _shownCallId;

  @override
  void dispose() {
    // Nettoie un éventuel heads-up d'appel encore affiché.
    InAppNotifier.instance.dismissCall();
    super.dispose();
  }

  void _openCallScreen() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const ActiveCallScreen(incoming: true),
    ));
  }

  void _showHeadsUp(
      CallController cc, String callId, String title, bool isVideo) {
    InAppNotifier.instance.showCall(
      title: title,
      isVideo: isVideo,
      onTap: () {
        InAppNotifier.instance.dismissCall();
        if (mounted) _openCallScreen();
      },
      onAccept: () async {
        await cc.acceptIncoming();
        if (mounted) _openCallScreen();
      },
      onReject: () {
        cc.rejectIncoming();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.watch<CallController>();
    final inc = cc.incoming;

    if (inc != null && inc.callId != _shownCallId) {
      // Nouvel appel entrant → on affiche le heads-up (après le frame courant).
      _shownCallId = inc.callId;
      final title = inc.displayTitle;
      final isVideo = inc.callType == "VIDEO";
      DebugOverlay.log("CL 📞 heads-up in-app: $title");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || cc.incoming?.callId != inc.callId) return;
        _showHeadsUp(cc, inc.callId, title, isVideo);
      });
    } else if (inc == null && _shownCallId != null) {
      // L'appel n'est plus entrant (accepté/rejeté/annulé) → on retire le heads-up.
      _shownCallId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        InAppNotifier.instance.dismissCall();
      });
    }

    return widget.child;
  }
}
