import 'dart:async';
import 'package:flutter/material.dart';

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
        widget.child,
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
