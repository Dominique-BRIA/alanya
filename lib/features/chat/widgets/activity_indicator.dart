import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/alanya_theme.dart';

/// Bandeau d'activité du correspondant, affiché au-dessus de la barre de
/// saisie : « en train d'écrire… » (3 points dansants décalés) ou « en train
/// d'enregistrer un vocal… » (onde animée organique). Animations différenciées.
class ActivityIndicatorBar extends StatelessWidget {
  const ActivityIndicatorBar({
    super.key,
    required this.typing,
    required this.recording,
    this.name,
  });

  /// Le correspondant est en train d'écrire.
  final bool typing;

  /// Le correspondant enregistre un vocal (priorité sur [typing]).
  final bool recording;

  /// Nom à préfixer (utile en groupe). En 1-à-1, laisser `null`.
  final String? name;

  bool get _visible => typing || recording;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !_visible
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: recording
                    ? _RecordingContent(name: name, key: const ValueKey('rec'))
                    : _TypingContent(name: name, key: const ValueKey('typ')),
              ),
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, required this.accent, super.key});
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: dark
              ? accent.withValues(alpha: 0.16)
              : accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: child,
      ),
    );
  }
}

class _TypingContent extends StatelessWidget {
  const _TypingContent({this.name, super.key});
  final String? name;

  @override
  Widget build(BuildContext context) {
    const accent = AlanyaColors.forest;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = name == null ? "en train d'écrire" : "$name écrit";
    return _Pill(
      accent: accent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TypingDots(color: accent),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: dark ? AlanyaColors.forestLight : accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingContent extends StatelessWidget {
  const _RecordingContent({this.name, super.key});
  final String? name;

  @override
  Widget build(BuildContext context) {
    const accent = AlanyaColors.terracotta;
    final label =
        name == null ? "en train d'enregistrer un vocal" : "$name enregistre";
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _Pill(
      accent: accent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded,
              size: 16, color: dark ? AlanyaColors.terracottaLight : accent),
          const SizedBox(width: 8),
          const RecordingWave(color: accent),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: dark ? AlanyaColors.terracottaLight : accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 points qui montent et descendent en décalé (staggered bounce).
class TypingDots extends StatefulWidget {
  const TypingDots({
    super.key,
    this.color = AlanyaColors.forest,
    this.dotSize = 7,
    this.amplitude = 5,
  });

  final Color color;
  final double dotSize;
  final double amplitude;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.dotSize + widget.amplitude,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              // Chaque point est déphasé → effet de vague naturel (non robotique).
              final phase = (_c.value + i * 0.2) % 1.0;
              final lift = math.sin(phase * math.pi).clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                child: Transform.translate(
                  offset: Offset(0, -widget.amplitude * lift),
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.55 + 0.45 * lift),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Onde/waveform animée, mouvement continu et organique (barres verticales
/// dont la hauteur oscille avec un léger déphasage — style signal audio).
class RecordingWave extends StatefulWidget {
  const RecordingWave({
    super.key,
    this.color = AlanyaColors.terracotta,
    this.barCount = 16,
    this.height = 22,
  });

  final Color color;
  final int barCount;
  final double height;

  @override
  State<RecordingWave> createState() => _RecordingWaveState();
}

class _RecordingWaveState extends State<RecordingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 2 * math.pi;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (i) {
              // Deux fréquences croisées → déformation progressive irrégulière
              // (comme portée par le vent), pas un simple sinus régulier.
              final a = math.sin(t + i * 0.55);
              final b = math.sin(t * 0.5 + i * 0.9);
              final v = (0.5 + 0.5 * a * b).abs().clamp(0.08, 1.0);
              final h = 3 + (widget.height - 3) * v;
              return Padding(
                padding:
                    EdgeInsets.only(right: i < widget.barCount - 1 ? 2 : 0),
                child: Container(
                  width: 2.6,
                  height: h,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.45 + 0.45 * v),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
