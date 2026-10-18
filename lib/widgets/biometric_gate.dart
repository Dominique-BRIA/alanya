import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/biometric_service.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/screens/biometric_lock_screen.dart';
import '../features/calls/call_controller.dart';
import '../theme/alanya_theme.dart';

/// Absence en arrière-plan au-delà de laquelle l'empreinte est redemandée.
const delaiReverrouillage = Duration(seconds: 30);

/// Faut-il redemander l'empreinte au retour au premier plan ?
///
/// [quitteeA] est l'heure du passage en arrière-plan (`paused` / `hidden`),
/// `null` si l'application n'y est pas passée.
///
/// ⚠️ `inactive` N'EN FAIT PAS PARTIE : Android l'envoie dès que la fenêtre
/// perd le focus — volet des notifications, boîte de dialogue système, et la
/// fenêtre d'empreinte ELLE-MÊME. Le compter redemanderait l'empreinte « à
/// chaque action ». Ouvrir la galerie ou l'appareil photo met l'application en
/// pause quelques secondes : le délai de grâce les couvre (même règle que
/// l'application Talky de l'équipe, branche `coffrefort`, 18/10/2026).
bool empreinteExigeeAuRetour({
  required DateTime? quitteeA,
  required DateTime maintenant,
  Duration grace = delaiReverrouillage,
}) {
  if (quitteeA == null) return false;
  return maintenant.difference(quitteeA) >= grace;
}

/// Le verrou par empreinte, POSÉ PAR-DESSUS l'application.
///
/// 🐛 L'ANCIEN VERROU REMPLAÇAIT L'ACCUEIL (« le verrouillage avec empreinte
/// dérange encore », user, 18/10/2026) : tant qu'il était affiché, rien
/// n'existait derrière — ni l'accueil, qui ne commençait à charger qu'après le
/// déverrouillage, ni l'écoute des appels entrants. Et il ne protégeait que le
/// lancement : revenir dans l'application ne redemandait rien.
///
/// Désormais :
/// * l'application vit DERRIÈRE le voile — elle charge pendant qu'on pose le
///   doigt, et le déverrouillage la montre telle qu'on l'a laissée (défilement
///   et saisie compris) ;
/// * le voile est OPAQUE et l'application dessous ne reçoit ni toucher ni
///   lecteur d'écran ;
/// * au retour, l'empreinte n'est redemandée qu'après [delaiReverrouillage]
///   en arrière-plan (voir [empreinteExigeeAuRetour]) ;
/// * un appel au premier plan (sonnerie ou écran d'appel) n'est jamais caché :
///   on décroche sans déverrouiller, comme sur WhatsApp. Le voile revient dès
///   que l'écran d'appel se ferme ou se réduit.
///
/// Placé dans `MaterialApp.builder`, il couvre TOUTES les pages, y compris une
/// discussion ouverte depuis une notification.
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate>
    with WidgetsBindingObserver {
  /// Le réglage n'est pas encore lu : on ne montre RIEN, ni contenu ni verrou.
  bool _reglageLu = false;
  bool _actif = false;

  /// Vrai tant que l'empreinte n'a pas validé l'accès depuis le dernier
  /// lancement (ou la dernière absence trop longue).
  bool _verrouille = true;

  DateTime? _quitteeA;
  bool _sessionOuverte = false;

  /// Chaque reverrouillage monte un écran NEUF, qui relance l'empreinte.
  int _tentative = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lireReglage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lireReglage() async {
    final actif = await BiometricService.isEnabled() &&
        await BiometricService.isAvailable();
    if (!mounted) return;
    setState(() {
      _actif = actif;
      _reglageLu = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Une NOUVELLE session (connexion après déconnexion) se déverrouille à
    // nouveau, et relit le réglage : le compte précédent l'a peut-être changé.
    final ouverte = Provider.of<AuthController>(context).status ==
        AuthStatus.authenticated;
    if (ouverte && !_sessionOuverte) {
      _verrouille = true;
      unawaited(_lireReglage());
    }
    _sessionOuverte = ouverte;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!BiometricService.authentificationEnCours) {
          _quitteeA ??= DateTime.now();
        }
        break;
      case AppLifecycleState.resumed:
        // La fenêtre du code de l'appareil met l'application en pause : son
        // retour n'est pas un retour de l'utilisateur.
        if (BiometricService.authentificationEnCours) {
          _quitteeA = null;
          break;
        }
        final exiger = empreinteExigeeAuRetour(
            quitteeA: _quitteeA, maintenant: DateTime.now());
        _quitteeA = null;
        if (!exiger) break;
        // Voile uni le temps de relire le réglage : jamais le contenu entre deux.
        setState(() {
          _verrouille = true;
          _tentative++;
          _reglageLu = false;
        });
        // Le réglage a pu changer pendant l'absence (écran Paramètres).
        unawaited(_lireReglage());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _deverrouiller() {
    if (!mounted) return;
    setState(() {
      _verrouille = false;
      _quitteeA = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appels = context.watch<CallController>();
    final appelAuPremierPlan =
        appels.callScreenVisible || appels.incoming != null;
    final protege = _sessionOuverte && (!_reglageLu || (_actif && _verrouille));
    final voile = protege && !appelAuPremierPlan;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: voile,
          child: IgnorePointer(ignoring: voile, child: widget.child),
        ),
        if (voile)
          // Le réglage pas encore lu : un fond uni, quelques millisecondes,
          // plutôt que le contenu qu'on cherche peut-être à protéger.
          !_reglageLu
              ? ColoredBox(color: surfacesOf(context).fond)
              : BiometricLockScreen(
                  key: ValueKey(_tentative),
                  onUnlocked: _deverrouiller,
                  onDisabled: () => setState(() => _actif = false),
                ),
      ],
    );
  }
}
