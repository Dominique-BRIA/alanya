import 'dart:async';
import 'package:flutter/material.dart';

/// Affiche les traces d'appel par-dessus l'application.
///
/// Laissé à `false` : c'est un outil de diagnostic, pas une fonctionnalité.
/// Le repasser à `true` rebranche l'overlay sans rien toucher d'autre — il a
/// permis d'identifier, en une seule capture d'écran, une course que plusieurs
/// correctifs raisonnés n'avaient pas su trouver. Les traces continuent de
/// partir dans le journal système (`adb logcat`), où elles ne coûtent rien.
/// ⚠️ REMIS À `true` LE 12/08/2026, TEMPORAIREMENT, pour l'invite vocale du
/// standard qui reste muette. Deux tours de correctifs raisonnés n'ont rien
/// donné : le bandeau affiche les traces SUR LE TÉLÉPHONE, sans `adb`, ce qui
/// avait déjà été décisif en août pour les appels. À repasser à `false` dès que
/// la cause est connue — ce bandeau n'a rien à faire dans un APK publié.
const bool tracesAppelsVisibles = true;

/// Trace de négociation d'appel : journal système ET overlay à l'écran.
///
/// Les deux, parce qu'ils ne servent pas au même moment : `adb logcat` donne
/// l'horodatage précis et l'historique complet, l'overlay permet de constater
/// sur le téléphone, sans câble, où la négociation s'arrête.
void traceAppel(String ligne) {
  debugPrint("[APPEL] $ligne");
  DebugOverlay.log("📞 $ligne");
}

/// Overlay de debug pour voir en live les événements WS et l'état du CallController.
/// À afficher au-dessus du Scaffold pendant le débogage des appels.
/// Retire ce widget en production.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key, required this.child});
  final Widget child;

  static final _log = <String>[];
  static final _controller = StreamController<void>.broadcast();

  /// Log une ligne. Appelable depuis n'importe où (RealtimeClient, CallController, etc.).
  static void log(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$ts $line');
    // 60 et non 20 : une négociation produit une rafale de candidats ICE qui
    // chassait du journal les lignes décisives — dont l'offre elle-même, la
    // seule qu'on cherchait.
    if (_log.length > 60) _log.removeLast();
    _controller.add(null);
  }

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _expanded = true; // Ouvert par défaut pour ne rien rater
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = DebugOverlay._controller.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // `Positioned.fill` et non l'enfant nu : dans un `Stack`, un enfant
        // non positionné se dimensionne sur son propre contenu. L'application
        // entière doit occuper toute la surface, quoi qu'affiche l'overlay.
        Positioned.fill(child: widget.child),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 4,
          left: _expanded ? 4 : null,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🐛 DEBUG WS/CALL (tap pour réduire)',
                            style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (DebugOverlay._log.isEmpty)
                            const Text('(en attente…)',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 9)),
                          ...DebugOverlay._log.take(15).map(
                                (l) => Text(
                                  l,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                        ],
                      )
                    : const Text('🐛', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
