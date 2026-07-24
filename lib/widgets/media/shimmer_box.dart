import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';

/// Placeholder « shimmer » animé (chargement) — un reflet clair balaye un fond
/// sable, façon WhatsApp. Optionnellement une barre de progression en bas.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.progress, // 0..1 ; null = indéterminé (pas de barre)
  });

  final double? width;
  final double? height;
  final double? progress;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = AlanyaColors.sand;
    const highlight = Color(0xFFF6F1EA);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1
        return Container(
          width: widget.width,
          height: widget.height ?? 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 - 2 * (1 - t), 0),
              end: Alignment(1.0 + 2 * t, 0),
              colors: const [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          alignment: Alignment.bottomCenter,
          child: widget.progress != null
              ? LinearProgressIndicator(
                  value: widget.progress!.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(
                    AlanyaColors.terracotta,
                  ),
                )
              : null,
        );
      },
    );
  }
}
