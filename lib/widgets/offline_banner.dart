import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/connectivity_service.dart';
import '../theme/alanya_theme.dart';
import '../l10n/app_localizations.dart';

/// « En attente de connexion… », quand l'app est hors ligne (voir
/// [ConnectivityService] pour ce qui compte comme « hors ligne »).
///
/// 🔴 UNE PASTILLE ROUGE QUI FLOTTE, PLUS UN BANDEAU (user, 30/10/2026 : « son
/// format n'est pas joli, mais j'aime bien la couleur rouge qui révèle
/// l'alerte »). Elle se pose SOUS la barre d'état, par-dessus l'écran, sans
/// rien déplacer ; elle laisse passer les touchers.
///
/// 🔴 ELLE SE REPLIE APRÈS QUELQUES SECONDES (user, 06/11/2026) : restée en
/// place, elle couvrait le nom de l'application. Le texte se rétracte, la
/// pastille s'efface, et l'alerte continue sous la forme d'une icône wifi
/// barrée dans l'en-tête de l'accueil — voir [IndicateurHorsLigne].
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  /// Le temps de lire le message avant qu'il ne se replie.
  static const _lecture = Duration(seconds: 3);
  static const _animation = Duration(milliseconds: 300);

  bool? _horsLignePrecedent;
  bool _texte = false;
  bool _visible = false;
  Timer? _repli;
  Timer? _effacement;

  @override
  void dispose() {
    _repli?.cancel();
    _effacement?.cancel();
    super.dispose();
  }

  void _suivre(bool horsLigne) {
    if (_horsLignePrecedent == horsLigne) return;
    _horsLignePrecedent = horsLigne;
    _repli?.cancel();
    _effacement?.cancel();
    if (!horsLigne) {
      _texte = false;
      _visible = false;
      return;
    }
    // Perte de connexion : le message en entier, puis il se replie sur son
    // icône, puis la pastille s'efface.
    _texte = true;
    _visible = true;
    _repli = Timer(_lecture, () {
      if (!mounted) return;
      setState(() => _texte = false);
      _effacement = Timer(_animation, () {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final horsLigne = context.watch<ConnectivityService>().isOffline;
    _suivre(horsLigne);
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                duration: _animation,
                curve: Curves.easeOut,
                offset: _visible ? Offset.zero : const Offset(0, -1.5),
                child: AnimatedOpacity(
                  duration: _animation,
                  opacity: _visible ? 1 : 0,
                  // ⚠️ Material INDISPENSABLE : posée par AuthGate hors de tout
                  // Scaffold, sans lui le texte prend le style de secours de
                  // Flutter, souligné de deux traits jaunes.
                  child: Material(
                    color: dangerOf(context),
                    elevation: 4,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: AnimatedSize(
                        duration: _animation,
                        curve: Curves.easeInOut,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off,
                                size: 15, color: Colors.white),
                            if (_texte) ...[
                              const SizedBox(width: 8),
                              Text(
                                tr(context, 'waiting_for_connection_dots'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// L'icône wifi barrée de l'en-tête de l'accueil, entre le nom de
/// l'application et le bouton de thème, tant que la connexion manque
/// (06/11/2026). C'est là que se replie la pastille [OfflineBanner].
class IndicateurHorsLigne extends StatelessWidget {
  const IndicateurHorsLigne({super.key});

  @override
  Widget build(BuildContext context) {
    final horsLigne = context.watch<ConnectivityService>().isOffline;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (enfant, animation) =>
          ScaleTransition(scale: animation, child: enfant),
      child: horsLigne
          ? Tooltip(
              key: const ValueKey('hors-ligne'),
              message: tr(context, 'waiting_for_connection'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.wifi_off, size: 20, color: dangerOf(context)),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('en-ligne')),
    );
  }
}
