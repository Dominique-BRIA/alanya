import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:provider/provider.dart';

import '../../core/call_ui_native.dart';
import '../../core/debug_overlay.dart';
import '../../core/in_app_notifier.dart';
import '../../core/push_service.dart';
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
/// Reçoit aussi les actions tapées sur la **notification système** d'appel
/// (Répondre / Refuser) via [PushService.onCallAction] : quand l'app se lance
/// depuis « Répondre », la trame d'appel bufferisée ré-arrive et on accepte
/// automatiquement.
class CallListener extends StatefulWidget {
  const CallListener({super.key, required this.child});
  final Widget child;

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  String? _shownCallId;
  bool _pendingAccept = false;
  StreamSubscription<CallEvent?>? _natifSub;

  @override
  void initState() {
    super.initState();
    // Actions de la notification système d'appel (Répondre / Refuser).
    PushService.onCallAction = _onCallAction;

    // Boutons de l'ÉCRAN D'APPEL NATIF. Ils n'arrivent pas par le même chemin
    // que ceux de la notification locale : c'est un flux propre au paquet, et
    // c'est lui qui compte désormais pour un appel reçu application fermée.
    _natifSub = FlutterCallkitIncoming.onEvent.listen((event) {
      if (!mounted || event == null) return;
      switch (event.event) {
        case Event.actionCallAccept:
          _onCallAction('call_accept', event.body['id']?.toString());
          break;
        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          _onCallAction('call_reject', event.body['id']?.toString());
          break;
        default:
          break;
      }
    });

    // Un écran d'appel laissé affiché par un arrêt brutal sonnerait dans le
    // vide au redémarrage : on repart d'une ardoise propre.
    CallUiNative.toutMasquer();
  }

  @override
  void dispose() {
    PushService.onCallAction = null;
    _natifSub?.cancel();
    // Nettoie un éventuel heads-up d'appel encore affiché.
    InAppNotifier.instance.dismissCall();
    super.dispose();
  }

  void _onCallAction(String actionId, String? callId) {
    if (!mounted) return;
    final cc = context.read<CallController>();
    if (actionId == 'call_reject') {
      cc.rejectIncoming();
      InAppNotifier.instance.dismissCall();
    } else if (actionId == 'call_accept') {
      if (cc.incoming != null) {
        cc.acceptIncoming().then((_) {
          if (mounted) _openCallScreen();
        });
      } else {
        // L'app vient de se lancer : la trame d'appel bufferisée va arriver
        // (buffer serveur 60 s) → on accepte dès qu'elle est là.
        _pendingAccept = true;
      }
    }
  }

  void _openCallScreen() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const ActiveCallScreen(incoming: true),
    ));
  }

  void _showHeadsUp(CallController cc, String callId, String title, bool isVideo,
      {String? avatarUrl}) {
    InAppNotifier.instance.showCall(
      title: title,
      avatarUrl: avatarUrl,
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
      _shownCallId = inc.callId;
      final title = inc.displayTitle;
      final isVideo = inc.callType == "VIDEO";
      final autoAccept = _pendingAccept;
      _pendingAccept = false;
      DebugOverlay.log("CL 📞 appel entrant: $title (auto=$autoAccept)");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || cc.incoming?.callId != inc.callId) return;
        if (autoAccept) {
          // Accepté depuis le bouton « Répondre » de la notification système.
          await cc.acceptIncoming();
          if (mounted) _openCallScreen();
        } else {
          _showHeadsUp(cc, inc.callId, title, isVideo,
              avatarUrl: inc.callerAvatarUrl);
        }
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
