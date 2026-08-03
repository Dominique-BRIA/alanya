import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/call_ui_native.dart';
import '../../core/debug_overlay.dart';
import '../../core/in_app_notifier.dart';
import '../../core/push_service.dart';
import 'call_controller.dart';
import 'calls_repository.dart';
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
    // `CallEvent` est une classe SCELLÉE : chaque action est une sous-classe
    // distincte, avec ses propres champs. On filtre donc sur le TYPE et non sur
    // une chaîne — le compilateur vérifie alors que les champs lus existent.
    _natifSub = FlutterCallkitIncoming.onEvent.listen((event) {
      if (!mounted || event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          _onCallAction('call_accept', callKitParams.id);
        case CallEventActionCallDecline(:final callKitParams):
          _onCallAction('call_reject', callKitParams.id);
        // Fin du délai de sonnerie : l'appel n'a pas été pris. Traité comme un
        // refus pour que l'appelant cesse de sonner tout de suite, plutôt que
        // d'attendre son propre minuteur.
        case CallEventActionCallTimeout(:final id):
          _onCallAction('call_reject', id);
        default:
          break;
      }
    });

    // ⚠️ NE PAS effacer les appels natifs au démarrage. La version précédente
    // appelait `endAllCalls()` ici pour nettoyer un écran orphelin — sauf que
    // décrocher DÉMARRE l'application : cette ligne supprimait donc l'appel que
    // l'utilisateur venait précisément d'accepter. L'écran se refermait, le
    // WebSocket relivrait l'appel bufferisé, et tout repartait à zéro comme
    // s'il arrivait à l'instant. Un écran vraiment orphelin disparaît seul au
    // bout des 60 s de sonnerie.
    _reprendreAppelNatif();
  }

  /// Récupère une action décidée AVANT que cet écouteur n'existe.
  ///
  /// Décrocher depuis l'écran natif démarre l'application : l'événement part
  /// alors que rien ne l'écoute encore, et il n'est jamais rejoué. Les appels
  /// actifs, eux, portent l'information — un appel marqué accepté signifie que
  /// l'utilisateur a appuyé sur Répondre.
  Future<void> _reprendreAppelNatif() async {
    try {
      final actifs = await FlutterCallkitIncoming.activeCalls();
      if (!mounted || actifs.isEmpty) return;
      for (final appel in actifs) {
        if (appel.isAccepted) {
          _onCallAction('call_accept', appel.id);
          return;
        }
      }
    } catch (_) {}
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
      if (cc.incoming != null) {
        cc.rejectIncoming();
      } else if (callId != null && callId.isNotEmpty) {
        // Refus décidé avant que l'appel ne soit connu de l'application —
        // typiquement au démarrage, la trame WebSocket n'étant pas encore
        // arrivée. `rejectIncoming` ne ferait rien du tout dans ce cas : il
        // commence par lire `incoming`, qui vaut nul. On prévient donc le
        // serveur directement, avec l'identifiant que l'écran natif nous donne,
        // sinon l'appelant sonnerait jusqu'à expiration.
        context.read<CallsRepository>().reject(callId).catchError((_) {});
        CallUiNative.masquer(callId);
      }
      InAppNotifier.instance.dismissCall();
    } else if (actionId == 'call_accept') {
      if (cc.incoming != null) {
        cc.acceptIncoming().then((_) {
          if (mounted) _openCallScreen();
        });
      } else if (callId != null && callId.isNotEmpty) {
        // Décrocher a DÉMARRÉ l'application : `incoming` est encore vide, la
        // trame WebSocket n'étant pas arrivée. On accepte avec le seul
        // identifiant plutôt que d'attendre — attendre laissait l'utilisateur
        // sur l'accueil, sans rien qui indique qu'un appel venait d'être pris.
        _accepteEtOuvre(cc, callId);
      } else {
        // Aucun identifiant : il ne reste qu'à attendre la trame.
        _pendingAccept = true;
      }
    }
  }

  Future<void> _accepteEtOuvre(CallController cc, String callId) async {
    final ok = await cc.acceptById(callId);
    if (!mounted) return;
    if (ok) {
      _openCallScreen();
    } else {
      // L'appel s'est terminé pendant le démarrage de l'application. On le dit,
      // plutôt que de laisser l'utilisateur devant un accueil muet après avoir
      // appuyé sur Répondre.
      showAppSnackBar("Cet appel n'est plus disponible");
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
