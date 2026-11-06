import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../core/push_service.dart';
import '../../widgets/avatar_circle.dart';
import 'call_controller.dart';
import 'screens/active_call_screen.dart';

/// LA FENÊTRE FLOTTANTE DU SYSTÈME (Android), pendant un appel vidéo
/// (06/11/2026), comme WhatsApp : on quitte l'application, l'image du
/// correspondant reste à l'écran au-dessus des autres applications.
///
/// Le pont natif est `PipBridge.kt`. Le contrôleur dit ici, à chaque
/// changement, si un appel vidéo est en cours ([definirEligible]) : Android
/// n'accepte d'ouvrir la fenêtre que depuis `onUserLeaveHint`, l'éligibilité
/// doit donc être connue AVANT que l'utilisateur appuie sur Accueil.
class FenetrePip extends ChangeNotifier with WidgetsBindingObserver {
  FenetrePip._();
  static final FenetrePip instance = FenetrePip._();

  static const _canal = MethodChannel('alanya/pip');

  bool _enFenetre = false;
  bool _eligible = false;
  bool _branche = false;

  /// L'application est affichée dans la fenêtre du système.
  bool get enFenetre => _enFenetre;

  void _brancher() {
    if (_branche || kIsWeb) return;
    _branche = true;
    _canal.setMethodCallHandler((call) async {
      if (call.method != 'onPipModeChanged') return null;
      final enFenetre = call.arguments == true;
      if (_enFenetre == enFenetre) return null;
      _enFenetre = enFenetre;
      notifyListeners();
      return null;
    });
  }

  Future<void> definirEligible(bool eligible) async {
    if (kIsWeb || _eligible == eligible) return;
    _eligible = eligible;
    try {
      _brancher();
      // L'observateur ne vit que le temps de l'appel vidéo, et son inscription
      // TARDIVE fait sa sûreté : voir [didPopRoute].
      if (eligible) {
        WidgetsBinding.instance.addObserver(this);
      } else {
        WidgetsBinding.instance.removeObserver(this);
        if (_enFenetre) {
          _enFenetre = false;
          notifyListeners();
        }
      }
      await _canal.invokeMethod('setEligible', {'eligible': eligible});
    } on MissingPluginException {
      // Plateforme sans pont (tests, iOS pour l'instant) : pas de fenêtre.
    } catch (e) {
      debugPrint('[FenetrePip] setEligible: $e');
    }
  }

  Future<bool> entrerMaintenant() async {
    try {
      return await _canal.invokeMethod<bool>('enterNow') == true;
    } catch (_) {
      return false;
    }
  }

  /// Le retour arrière allait FERMER l'application : on ouvre la fenêtre.
  ///
  /// Android ne passe par `onUserLeaveHint` que pour le bouton Accueil ; le
  /// retour arrière termine l'activité, et l'appel vidéo avec elle. Sur
  /// l'API 31+, l'entrée automatique couvre déjà ce chemin ; en dessous, c'est
  /// le seul rattrapage. Inscrit APRÈS le `Navigator`, cet observateur ne voit
  /// que le retour que personne n'a pris en charge — celui qui quitterait.
  @override
  Future<bool> didPopRoute() async {
    if (!_eligible || _enFenetre) return false;
    return entrerMaintenant();
  }
}

/// La vidéo de l'appel HORS de son écran (06/11/2026) :
///
///  * dans la fenêtre du système, toute l'application se réduit à l'image du
///    correspondant — le reste, dans une vignette, ne serait que du bruit ;
///  * dans l'application, écran d'appel réduit, une petite fenêtre déplaçable
///    remplace le bandeau : on continue de voir le correspondant en écrivant
///    un message. Un appui ramène à l'appel.
class FenetreVideoAppel extends StatefulWidget {
  const FenetreVideoAppel({super.key});

  @override
  State<FenetreVideoAppel> createState() => _FenetreVideoAppelState();
}

class _FenetreVideoAppelState extends State<FenetreVideoAppel> {
  RTCVideoRenderer? _rendu;
  bool _renduPret = false;
  Offset? _position;

  static const _largeur = 112.0;
  static const _hauteur = 160.0;

  @override
  void initState() {
    super.initState();
    FenetrePip.instance.addListener(_actualiser);
  }

  @override
  void dispose() {
    FenetrePip.instance.removeListener(_actualiser);
    _rendu?.dispose();
    super.dispose();
  }

  void _actualiser() {
    if (mounted) setState(() {});
  }

  Future<void> _assurerRendu(MediaStream? flux) async {
    if (_rendu == null) {
      final r = RTCVideoRenderer();
      _rendu = r;
      await r.initialize();
      if (!mounted) return;
      setState(() => _renduPret = true);
    }
    final r = _rendu;
    if (_renduPret && r != null && r.srcObject != flux) r.srcObject = flux;
  }

  /// Le correspondant montré : le premier dont la caméra est allumée.
  MapEntry<String, MediaStream>? _principal(CallController cc) {
    final flux = cc.remoteStreams.entries.toList();
    if (flux.isEmpty) return null;
    return flux.firstWhere(
      (e) => cc.cameraDistanteActive(e.key),
      orElse: () => flux.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.watch<CallController>();
    final videoEnCours = cc.activeCallId != null &&
        cc.activeType == "VIDEO" &&
        cc.activeRole == ActiveCallRole.ongoing;
    final enFenetre = FenetrePip.instance.enFenetre && videoEnCours;
    final reduite = videoEnCours && !cc.callScreenVisible;
    if (!enFenetre && !reduite) return const SizedBox.shrink();

    final principal = _principal(cc);
    unawaited(_assurerRendu(principal?.value));
    final avecImage = principal != null &&
        _renduPret &&
        cc.cameraDistanteActive(principal.key);
    final nom = principal != null
        ? (cc.participantNames[principal.key] ?? cc.activePeerName)
        : cc.activePeerName;
    final photo = principal != null
        ? (cc.participantAvatars[principal.key] ?? cc.activePeerAvatarUrl)
        : cc.activePeerAvatarUrl;

    final image = avecImage
        ? RTCVideoView(
            _rendu!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        : ColoredBox(
            color: const Color(0xFF1C1C1E),
            child: Center(
              child: AvatarCircle(
                name: nom,
                avatarUrl: photo,
                radius: enFenetre ? 40 : 28,
              ),
            ),
          );

    if (enFenetre) {
      return Positioned.fill(child: ColoredBox(color: Colors.black, child: image));
    }

    final taille = MediaQuery.sizeOf(context);
    final marge = MediaQuery.paddingOf(context);
    final pos = _position ??
        Offset(taille.width - _largeur - 12, marge.top + 12);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => PushService.navigatorKey.currentState?.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ActiveCallScreen(incoming: false),
          ),
        ),
        onPanUpdate: (d) {
          setState(() {
            final p = (_position ?? pos) + d.delta;
            _position = Offset(
              p.dx.clamp(4, taille.width - _largeur - 4),
              p.dy.clamp(marge.top + 4, taille.height - _hauteur - marge.bottom - 4),
            );
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: _largeur, height: _hauteur, child: image),
        ),
      ),
    );
  }
}
