import 'dart:async';

import 'package:alanya_telecom/alanya_telecom.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:provider/provider.dart';

import '../../core/app_snackbar.dart';
import '../../core/call_ui_native.dart';
import '../../core/debug_overlay.dart';
import '../../core/diagnostic_chip.dart';
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

    // Boutons de la notification TELECOM, portée par le module natif local.
    //
    // C'est désormais CE canal qui compte sur Android : `afficherAppelEntrant`
    // passe par Telecom en priorité, et le flux du paquet juste au-dessus ne
    // sert plus qu'au repli. Sans cet écouteur, Décrocher et Refuser seraient
    // des boutons morts pour tout appel reçu application fermée.
    AlanyaTelecom.setListener((event, data) {
      if (!mounted) return;
      final callId = data['callId']?.toString();
      switch (event) {
        case 'answer':
          // Traces du chip, POSÉES AVANT la garde d'écho : sur le chemin de
          // l'écho la branche sort tout de suite, et le diagnostic serait
          // perdu justement quand on décroche depuis l'application.
          // Deux relevés : le natif écrit en `apply()` (asynchrone) et le
          // service ne pose sa notification qu'un instant plus tard — un seul
          // relevé raterait la ligne décisive.
          unawaited(Future.delayed(
              const Duration(milliseconds: 1500), verserTracesChip));
          unawaited(Future.delayed(
              const Duration(seconds: 5), verserTracesChip));
          // Écho de notre propre `answerRinging` : l'appel est déjà en cours
          // d'acceptation, le relancer ouvrirait un second écran d'appel.
          if (CallUiNative.consommerEchoLocal(callId)) return;
          _onCallAction('call_accept', callId);
        // Le délai de sonnerie compte comme un refus, pour que l'appelant cesse
        // de sonner tout de suite plutôt que d'attendre son propre minuteur.
        case 'reject' || 'timeout':
          _onCallAction('call_reject', callId);
        case 'telecom_failed':
          unawaited(_replierSurPaquet(data));
        // Appui sur le chip vert de la barre d'état : on REVIENT à un appel
        // déjà décroché, on n'en accepte aucun. D'où une branche à part et
        // non un `call_accept`, qui relancerait une acceptation.
        case 'reopen':
          _rouvrirEcranAppel();
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

    // ── DIAGNOSTIC DU CHIP VERT ────────────────────────────────────────────
    // Trace-témoin : elle PROUVE que l'APK installé contient bien cette
    // version. Sans elle, un overlay vide se lit de deux façons — « le natif
    // n'a rien écrit » ou « ce n'est pas le bon APK » — et on a déjà perdu
    // plusieurs allers-retours sur cette ambiguïté.
    DebugOverlay.log('CL ✅ diagnostic chip actif');
    unawaited(verserTracesChip());
  }

  /// Récupère une action décidée AVANT que cet écouteur n'existe.
  ///
  /// Décrocher depuis l'écran natif démarre l'application : l'événement part
  /// alors que rien ne l'écoute encore, et il n'est jamais rejoué. Les appels
  /// actifs, eux, portent l'information — un appel marqué accepté signifie que
  /// l'utilisateur a appuyé sur Répondre.
  Future<void> _reprendreAppelNatif() async {
    // ── TELECOM D'ABORD ────────────────────────────────────────────────────
    // C'est lui qui porte l'appel sur Android ; le paquet n'intervient qu'en
    // repli. Ces deux accesseurs existent précisément pour le démarrage à
    // froid : l'événement `answer` est parti avant que cet écouteur n'existe,
    // et il n'est jamais rejoué — seul l'état de la `Connection` en garde la
    // trace.
    try {
      final accepte = await AlanyaTelecom.getAcceptedCall();
      if (!mounted) return;
      final idAccepte = accepte?['callId']?.toString();
      if (idAccepte != null && idAccepte.isNotEmpty) {
        _onCallAction('call_accept', idAccepte);
        return;
      }

      // ⚠️ NE PAS COUPER LA SONNERIE NATIVE ICI, si tentant que ce soit.
      //
      // Une version précédente appelait `silenceRinger()` à ce point, en
      // supposant que la sonnerie interne prendrait aussitôt le relais. Mesuré
      // sur TECNO KL5 : le son natif s'arrêtait à 3,1 s et l'interne ne
      // démarrait qu'à 16,0 s — HUIT SECONDES DE SILENCE. La raison est simple :
      // `RingtoneService` ne peut sonner qu'une fois la trame socket
      // `incoming_call` arrivée, et au démarrage à froid le WebSocket met une
      // dizaine de secondes à se connecter.
      //
      // On laisse donc le natif sonner sans interruption. C'est
      // `call_controller` qui s'abstient de lancer la sonnerie interne quand
      // celle-ci tourne déjà — une seule source, et aucun trou.
    } catch (_) {}

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

  /// Telecom avait accepté la déclaration, puis n'a pas créé la `Connection` —
  /// appel cellulaire en cours, ou compte refusé par le constructeur.
  ///
  /// Le repli ne pouvait pas être choisi au moment de la déclaration, puisque
  /// celle-ci avait réussi : sans ce rattrapage, l'appel disparaîtrait sans le
  /// moindre signe. `sansTelecom` empêche de repasser par la voie qui vient
  /// d'échouer.
  Future<void> _replierSurPaquet(Map<String, dynamic> data) async {
    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) return;
    DebugOverlay.log("CL ⚠️ Telecom indisponible → repli paquet ($callId)");
    try {
      await CallUiNative.afficherAppelEntrant(
        callId: callId,
        nom: data['callerName']?.toString() ?? 'Appel entrant',
        avatarUrl: data['callerAvatar']?.toString(),
        video: data['callType']?.toString() == 'video',
        sansTelecom: true,
      );
    } catch (e) {
      DebugOverlay.log("CL ❌ repli paquet indisponible : $e");
    }
  }

  @override
  void dispose() {
    PushService.onCallAction = null;
    AlanyaTelecom.setListener(null);
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
        // commence par lire `incoming`, qui vaut nul.
        _refuseParId(callId);
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

  /// Refuse un appel dont on ne connaît que l'identifiant, et VÉRIFIE que le
  /// serveur l'a bien enregistré.
  ///
  /// ⚠️ L'échec était avalé par un `catchError` muet. Conséquence observée : la
  /// notification disparaissait puis revenait sans cesse. Le serveur ne rejoue
  /// un appel bufferisé que s'il est encore en sonnerie — donc son retour
  /// signifiait, sans que rien ne le dise, que le refus n'était jamais parvenu.
  ///
  /// L'écran natif est fermé AVANT l'appel réseau : l'utilisateur a refusé, sa
  /// décision doit se voir tout de suite, même si le serveur met du temps.
  Future<void> _refuseParId(String callId) async {
    // Dépôt capturé AVANT tout await : le lire après reviendrait à toucher un
    // BuildContext qui peut avoir été démonté entre-temps.
    final repo = context.read<CallsRepository>();
    await CallUiNative.masquer(callId);
    try {
      await repo.reject(callId);
      DebugOverlay.log("CL ✅ refus transmis ($callId)");
    } catch (e) {
      // L'appelant continuera de sonner jusqu'à expiration. On le trace pour
      // que le journal de débogage le montre au lieu d'un silence.
      DebugOverlay.log("CL ❌ refus NON transmis : $e");
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

  /// Ouvre l'écran d'appel, en attendant que le navigateur existe.
  ///
  /// ⚠️ AU DÉMARRAGE À FROID, l'application vient d'être lancée par « Répondre »
  /// et son interface n'est pas encore construite : `Navigator.of(context)`
  /// échouait alors sans bruit. L'appel démarrait bel et bien, mais aucun écran
  /// ne s'ouvrait — d'où l'impression d'un appel invisible, poursuivi en
  /// arrière-plan sans moyen d'en connaître l'état.
  ///
  /// Le navigateur GLOBAL est utilisé plutôt que celui du contexte local, et on
  /// lui laisse le temps d'apparaître : une seconde par pas de 100 ms, largement
  /// au-delà du temps de construction observé.
  /// Retour à l'écran d'appel depuis le chip vert de la barre d'état.
  ///
  /// Distinct de [_openCallScreen] sur trois points, et chacun compte :
  ///
  /// 1. L'écran n'est PAS marqué `incoming`. Le marquer entrant déclencherait
  ///    `notifyRingingDisplayed()`, qui annonce « en train de sonner… » à
  ///    l'appelant — d'un appel qu'on a déjà décroché.
  /// 2. On ne pousse rien si l'écran est DÉJÀ affiché. Sans ce garde-fou, un
  ///    appui sur le chip alors qu'on est sur l'écran d'appel empilerait un
  ///    second écran par-dessus le premier, et il faudrait deux retours pour
  ///    en sortir.
  /// 3. Aucune boucle de reprise du navigateur : le chip n'existe que tant que
  ///    le processus vit, donc l'application tourne déjà. Le cas du démarrage
  ///    à froid, lui, est couvert par `_reprendreAppelNatif()`.
  ///
  /// `activeCallId` — et non le statut de l'appel — dit que c'est bien NOTRE
  /// appel sur CET appareil, pour la même raison que dans
  /// `ouvrirSiAppelEnCours` : un appel peut être en cours entre deux autres
  /// personnes d'un groupe, et son écran serait alors vide.
  void _rouvrirEcranAppel() {
    if (!mounted) return;
    final cc = context.read<CallController>();
    if (cc.activeCallId == null) return;
    if (cc.callScreenVisible) return;
    PushService.navigatorKey.currentState?.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const ActiveCallScreen(),
    ));
  }

  Future<void> _openCallScreen() async {
    for (var essai = 0; essai < 10; essai++) {
      final nav = PushService.navigatorKey.currentState;
      if (nav != null) {
        nav.push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(incoming: true),
        ));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Navigateur toujours absent : l'appel reste actif et le bandeau global
    // permet d'y revenir. Mieux vaut ça qu'une exception qui coupe tout.
    DebugOverlay.log("CL ⚠️ navigateur indisponible, écran d'appel non ouvert");
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
        } else if (!cc.ecranNatifAffiche) {
          // Repli seulement : quand l'écran natif porte l'appel, ce bandeau
          // ferait doublon — et c'est lui qu'on prenait pour une notification
          // de message, faute de sonnerie et de plein écran.
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
