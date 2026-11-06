import 'dart:async';

import 'package:alanya_telecom/alanya_telecom.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../core/appel_natif_prefs.dart';
import '../../core/call_ui_native.dart';
import '../../core/debug_overlay.dart';
import '../../core/diagnostic_chip.dart';
import '../../core/in_app_notifier.dart';
import '../../core/push_service.dart';
import 'appel_entrant_reduit.dart';
import 'call_controller.dart';
import 'widgets/feuille_repondeur.dart';
import 'calls_repository.dart';
import 'screens/active_call_screen.dart';
import '../../l10n/app_localizations.dart';

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

class _CallListenerState extends State<CallListener>
    with WidgetsBindingObserver {
  /// L'appel dont la feuille de repondeur est deja ouverte, ou `null`.
  String? _repondeurAffiche;

  String? _shownCallId;
  bool _pendingAccept = false;
  StreamSubscription<CallEvent?>? _natifSub;

  /// L'application est-elle à l'écran ? `null` au tout premier démarrage,
  /// avant le premier état : l'activité vient d'être lancée, donc visible.
  bool get _auPremierPlan {
    final etat = WidgetsBinding.instance.lifecycleState;
    return etat == null || etat == AppLifecycleState.resumed;
  }

  /*
   * PASSAGES DE RELAIS ENTRE L'ÉCRAN FLUTTER ET L'ÉCRAN NATIF (06/11/2026),
   * comme `decideIncomingPresentation` dans l'application de référence.
   *
   * - L'application QUITTE l'écran pendant que ça sonne (verrouillage,
   *   bouton Accueil) : l'appel est confié à l'écran natif CallKit, seul
   *   visible hors de l'application et par-dessus le verrouillage.
   * - Elle REVIENT : son écran de sonnerie reprend l'appel, l'écran natif est
   *   retiré sans fin ni refus (voir `CallController.prendreLaSonnerie`).
   */
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_presenterSonnerieEnAttente());
    } else if (state == AppLifecycleState.paused) {
      unawaited(context.read<CallController>().confierAuNatif());
    }
  }

  Future<void> _presenterSonnerieEnAttente() async {
    final cc = context.read<CallController>();
    // Refus restés en attente (réseau absent quand on a refusé) : le retour au
    // premier plan est souvent celui du réseau.
    unawaited(cc.rejouerRefusEnAttente());
    final natif = await CallUiNative.appelActif();
    if (!mounted) return;
    // Décroché sur l'écran natif : c'est ce décroché qui ramène l'application,
    // l'acceptation suit son propre chemin.
    if (natif?['isAccepted'] == true) return;
    if (cc.incoming == null && natif != null) cc.adopterAppelNatif(natif);
    final inc = cc.incoming;
    if (inc == null) return;
    if (!cc.callScreenVisible && cc.entrantReduit != inc.callId) {
      _shownCallId = inc.callId;
      await ouvrirEcranSonnerie(cc);
    }
    if (!mounted) return;
    unawaited(cc.prendreLaSonnerie(inc.callId));
  }

  /// Les libellés de l'écran natif, dans la langue de l'application. Republiés
  /// à chaque changement de langue : le natif ne peut pas la demander.
  void _publierLibellesNatifs() {
    const cles = ['accept', 'decline', 'incoming_calls', 'missed_calls'];
    final libelles = <String, String>{};
    for (final cle in cles) {
      try {
        // `tr` et non `trLu` : il ABONNE à la langue, et c'est ce qui fait
        // rappeler `didChangeDependencies` quand elle change.
        libelles[cle] = tr(context, cle);
      } catch (_) {}
    }
    unawaited(PontNatifAppel.publierLibelles(libelles));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publierLibellesNatifs();
  }

  /// L'identifiant SERVEUR d'une entrée CallKit : `extra.callId`, à défaut
  /// l'identifiant de l'entrée (ils coïncident aujourd'hui).
  static String _idServeur(CallKitParams p) {
    final metier = p.extra?['callId']?.toString().trim() ?? '';
    return metier.isNotEmpty ? metier : p.id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Actions de la notification système d'appel (Répondre / Refuser).
    PushService.onCallAction = _onCallAction;

    // Boutons de l'ÉCRAN D'APPEL NATIF (CallKit), application vivante.
    // `CallEvent` est une classe SCELLÉE : on filtre sur le TYPE, le
    // compilateur vérifie que les champs lus existent.
    _natifSub = FlutterCallkitIncoming.onEvent.listen((event) {
      if (!mounted || event == null) return;
      switch (event) {
        case CallEventActionCallAccept(:final callKitParams):
          _onCallAction('call_accept', _idServeur(callKitParams));
        // Refus : le NATIF l'envoie lui-même (AlanyaApplication →
        // CallRejectHelper). On nettoie sans le renvoyer, puis on reprend la
        // file un peu plus tard au cas où il aurait échoué (jeton expiré).
        case CallEventActionCallDecline(:final callKitParams):
          _onCallAction('call_reject', _idServeur(callKitParams),
              dejaTransmis: true);
          unawaited(Future<void>.delayed(const Duration(seconds: 6), () {
            if (mounted) context.read<CallController>().rejouerRefusEnAttente();
          }));
        // Sonnerie expirée : PAS un refus, comme dans la référence — le
        // minuteur du serveur la classe lui-même. État local seulement.
        case CallEventActionCallTimeout(:final id):
          unawaited(context.read<CallController>().finSignaleeParLeNatif(id));
        case CallEventActionCallEnded(:final callKitParams):
          unawaited(context
              .read<CallController>()
              .finSignaleeParLeNatif(_idServeur(callKitParams)));
        default:
          break;
      }
    });

    // Fin d'appel vue par le NATIF (écouteur ACTIVE_CALLS d'AlanyaApplication)
    // quand l'événement du paquet n'atteint pas Dart : refus ou raccroché
    // depuis la notification, expiration.
    _canalNatif.setMethodCallHandler((appel) async {
      if (!mounted || appel.method != 'onCallEnded') return;
      final args = appel.arguments;
      final callId = args is Map ? (args['callId']?.toString() ?? '') : '';
      await context.read<CallController>().finSignaleeParLeNatif(callId);
    });

    // Appui sur le chip vert de la barre d'état : on REVIENT à un appel déjà
    // décroché, on n'en accepte aucun.
    AlanyaTelecom.setListener((event, data) {
      if (!mounted) return;
      if (event == 'reopen') _rouvrirEcranAppel();
    });

    _reprendreAppelNatif();
    // Refus gardés sans réseau, ici ou application fermée (RefusEnAttente).
    unawaited(context.read<CallController>().rejouerRefusEnAttente());

    // ── DIAGNOSTIC DU CHIP VERT ────────────────────────────────────────────
    // Trace-témoin : elle PROUVE que l'APK installé contient bien cette
    // version.
    DebugOverlay.log('CL ✅ diagnostic chip actif');
    unawaited(verserTracesChip());
  }

  static const _canalNatif = MethodChannel('com.alanya/call_native');

  /*
   * DÉMARRAGE À FROID, comme `main.dart` dans l'application de référence.
   *
   * L'événement du paquet est parti avant que cet écouteur n'existe, et il
   * n'est jamais rejoué : seule l'entrée CallKit en garde la trace. Le
   * décrochage, lui, a été écrit avant même Flutter, par `MainActivity` qui l'a
   * lu dans son intent de lancement (`CallAcceptFromIntent`) — aucune course.
   *
   * - Entrée acceptée et récente → on décroche.
   * - Entrée qui sonne encore et récente → notre écran de sonnerie la reprend.
   * - Rien de plausible → les débris d'un essai précédent sont retirés, sans
   *   qu'aucun soit pris pour un refus.
   */
  Future<void> _reprendreAppelNatif() async {
    final natif = await CallUiNative.appelActif();
    if (!mounted) return;
    if (natif == null) {
      unawaited(CallUiNative.toutMasquer());
      return;
    }
    final callId = natif['callId']?.toString() ?? '';
    if (callId.isEmpty) return;
    if (natif['isAccepted'] == true) {
      _onCallAction('call_accept', callId);
      return;
    }
    context.read<CallController>().adopterAppelNatif(natif);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.onCallAction = null;
    AlanyaTelecom.setListener(null);
    _natifSub?.cancel();
    // Nettoie un éventuel heads-up d'appel encore affiché.
    InAppNotifier.instance.dismissCall();
    super.dispose();
  }

  /// [dejaTransmis] : le refus est déjà parti au serveur, par le natif — on
  /// ne fait que nettoyer l'état de l'application.
  void _onCallAction(String actionId, String? callId,
      {bool dejaTransmis = false}) {
    if (!mounted) return;
    final cc = context.read<CallController>();
    if (actionId == 'call_reject') {
      final inc = cc.incoming;
      // Un refus ne vise que SON appel : arrivé en retard, il ne doit pas
      // refuser l'appel suivant, qui sonne peut-être déjà (06/11/2026).
      final memeAppel =
          inc != null && (callId == null || callId.isEmpty || inc.callId == callId);
      if (memeAppel) {
        cc.rejectIncoming(transmettre: !dejaTransmis);
      } else if (callId != null && callId.isNotEmpty) {
        // Refus décidé avant que l'appel ne soit connu de l'application —
        // typiquement au démarrage, la trame WebSocket n'étant pas encore
        // arrivée. `rejectIncoming` ne ferait rien du tout dans ce cas : il
        // commence par lire `incoming`, qui vaut nul.
        if (dejaTransmis) {
          unawaited(CallUiNative.masquer(callId));
          unawaited(AppelsTermines.marquer(callId));
        } else {
          _refuseParId(callId);
        }
      }
      InAppNotifier.instance.dismissCall();
    } else if (actionId == 'call_accept') {
      final inc = cc.incoming;
      if (inc != null &&
          (callId == null || callId.isEmpty || inc.callId == callId)) {
        cc.acceptIncoming().then((_) {
          if (mounted) _openCallScreen();
        });
      } else if (callId != null && callId.isNotEmpty) {
        // Décroché d'un AUTRE appel que celui connu ici, ou :
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
    final cc = context.read<CallController>();
    await CallUiNative.masquer(callId);
    try {
      await repo.reject(callId);
      DebugOverlay.log("CL ✅ refus transmis ($callId)");
    } catch (e) {
      // Tracé pour que le journal de débogage le montre au lieu d'un silence.
      DebugOverlay.log("CL ❌ refus NON transmis : $e");
      // Pas de réseau : le refus est gardé et renvoyé tant que l'appel peut
      // encore sonner (06/11/2026), au lieu de laisser l'appelant sonner.
      if (e is! ApiException || e.statusCode >= 500) {
        unawaited(cc.refuserPlusTard(callId));
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
      showAppSnackBar(tr(context, 'call_no_longer_available'));
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
    final cc = context.read<CallController>();
    for (var essai = 0; essai < 10; essai++) {
      // Déjà affiché — décroché depuis la notification du système alors que
      // notre écran de sonnerie était ouvert : l'écran se met à jour seul, un
      // second par-dessus demanderait deux retours pour en sortir.
      if (cc.callScreenVisible) return;
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
        } else if (_auPremierPlan) {
          // L'ÉCRAN PLEIN, AUDIO COMME VIDÉO (06/11/2026). L'appel audio
          // n'avait qu'un bandeau en haut de l'écran, qu'on prenait pour une
          // notification de message. Le bandeau reste, mais comme forme
          // RÉDUITE de cet écran (flèche ou bouton retour).
          //
          // Application hors de l'écran : rien ici. L'écran natif porte
          // l'appel, et le nôtre s'ouvrira au retour au premier plan
          // (`didChangeAppLifecycleState`) — l'ouvrir en arrière-plan
          // allumerait la caméra de l'aperçu sans personne pour la voir.
          DebugOverlay.log(
              "CL 📞 écran de sonnerie (${isVideo ? 'vidéo' : 'audio'})");
          await ouvrirEcranSonnerie(cc);
          // Appel repris de l'écran natif (démarrage à froid) : l'écran
          // Flutter prend aussi la sonnerie. Sans effet si elle joue déjà.
          unawaited(cc.prendreLaSonnerie(inc.callId));
        }
      });
    }

    /*
     * LE REPONDEUR DU CORRESPONDANT.
     *
     * 🔴 ICI, ET NON DANS L'ECRAN D'APPEL. L'appel est deja clos quand le
     * serveur envoie `repondeur_direct` — il n'a jamais sonne — et l'ecran
     * d'appel se referme aussitot. Une feuille montee dedans disparaitrait a
     * l'instant meme ou elle devrait s'ouvrir. `CallListener` enveloppe
     * l'application entiere : il survit a cette fermeture.
     *
     * ⚠️ `_repondeurAffiche` GARDE L'IDENTIFIANT DE L'APPEL, et non un
     * booleen : le `build` se rejoue a chaque notification du controleur, et un
     * drapeau remis a zero a la fermeture rouvrirait la feuille en boucle tant
     * que la session vit.
     */
    final rep = cc.repondeur;
    if (rep != null && rep.callId != _repondeurAffiche) {
      _repondeurAffiche = rep.callId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const FeuilleRepondeur(),
        );
        // Ferme par le bas plutot que par le bouton : la session doit partir
        // quand meme, sinon elle rouvrirait la feuille au prochain `build`.
        if (mounted) context.read<CallController>().fermerRepondeur();
      });
    } else if (rep == null && _repondeurAffiche != null) {
      _repondeurAffiche = null;
    }

    if (inc == null && _shownCallId != null) {
      // L'appel n'est plus entrant (accepté/rejeté/annulé) → on retire le heads-up.
      _shownCallId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        InAppNotifier.instance.dismissCall();
      });
    }

    return widget.child;
  }
}
