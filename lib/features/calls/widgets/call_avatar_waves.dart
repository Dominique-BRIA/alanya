import 'package:flutter/material.dart';

/// Avatar entouré d'ondes animées (ripples concentriques) pour un appel audio,
/// façon WhatsApp — simule l'activité sonore.
class CallAvatarWaves extends StatefulWidget {
  const CallAvatarWaves({
    super.key,
    required this.child,
    this.diameter = 132,
    this.color = Colors.white,
    this.active = true,
  });

  /// L'avatar (déjà en forme de cercle).
  final Widget child;

  /// Diamètre de l'avatar.
  final double diameter;

  /// Couleur des ondes.
  final Color color;

  /// Si false, les ondes sont figées (appel en pause / non connecté).
  final bool active;

  @override
  State<CallAvatarWaves> createState() => _CallAvatarWavesState();
}

class _CallAvatarWavesState extends State<CallAvatarWaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(CallAvatarWaves old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.diameter * 2.3;
    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < 3; i++) _wave(i),
              widget.child,
            ],
          );
        },
      ),
    );
  }

  Widget _wave(int i) {
    // 3 ondes déphasées : chacune grandit de l'avatar vers ~2.2x en s'estompant.
    final t = (_c.value + i / 3) % 1.0;
    final size = widget.diameter * (1.0 + t * 1.2);
    final opacity = (1.0 - t) * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.color.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}
