import 'dart:async';
import 'package:flutter/material.dart';

/// DIAGNOSTIC TEMPORAIRE — affiche les traces d'appel par-dessus l'application.
///
/// L'overlay existait déjà mais n'était monté nulle part : `DebugOverlay.log`
/// remplissait une liste que personne n'affichait. Le laisser branché permet de
/// lire, sur le téléphone et sans `adb`, où la négociation s'interrompt.
///
/// ⚠️ À REPASSER À `false` une fois le problème d'appel réglé.
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
    if (_log.length > 20) _log.removeLast();
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
                            style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (DebugOverlay._log.isEmpty)
                            const Text('(en attente…)', style: TextStyle(color: Colors.white54, fontSize: 9)),
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
