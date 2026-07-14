import 'dart:async';

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'audio_state.dart';

/// Lecteur audio réactif pour le web (une piste à la fois).
///
/// Utilise [html.AudioElement] et expose l'état via [state] (un [ValueNotifier])
/// pour que l'UI affiche play/pause et la progression en temps réel.
class InlineAudioPlayer {
  // ignore: deprecated_member_use
  static html.AudioElement? _player;
  static String? _currentUrl;
  static StreamSubscription? _playingSub;
  static StreamSubscription? _pauseSub;
  static StreamSubscription? _endedSub;
  static StreamSubscription? _timeSub;
  static StreamSubscription? _durSub;

  /// Source unique de vérité pour l'UI. Singleton statique persistant.
  static final ValueNotifier<AudioPlaybackState> state =
      ValueNotifier(const AudioPlaybackState());

  /// Bascule play / pause pour une URL donnée.
  static Future<void> toggle(String url, {Duration? totalDuration}) async {
    if (_currentUrl == url && state.value.isPlaying) {
      await pause();
    } else if (_currentUrl == url) {
      await resume();
    } else {
      await play(url, totalDuration: totalDuration);
    }
  }

  static Future<void> play(String url, {Duration? totalDuration}) async {
    await _stopInternal();

    _currentUrl = url;
    // ignore: deprecated_member_use
    _player = html.AudioElement()..src = url;

    state.value = AudioPlaybackState(
      url: url,
      isPlaying: false,
      position: Duration.zero,
      duration: totalDuration,
    );

    _playingSub = _player.onPlaying.listen((_) {
      state.value = state.value.copyWith(isPlaying: true);
    });

    _pauseSub = _player.onPause.listen((_) {
      state.value = state.value.copyWith(isPlaying: false);
    });

    _endedSub = _player.onEnded.listen((_) {
      _stopInternal();
    });

    _timeSub = _player.onTimeUpdate.listen((_) {
      final p = _player;
      if (p == null) return;
      state.value = state.value.copyWith(
        position: Duration(milliseconds: (p.currentTime * 1000).round()),
      );
    });

    _durSub = _player.onDurationChange.listen((_) {
      final p = _player;
      if (p == null) return;
      final d = p.duration;
      if (!d.isNaN && !d.isInfinite && d > 0) {
        state.value = state.value.copyWith(
          duration: Duration(milliseconds: (d * 1000).round()),
        );
      }
    });

    try {
      await _player.play();
    } catch (_) {
      // Certains navigateurs bloquent l'autoplay sans interaction utilisateur.
      // L'utilisateur devra appuyer une seconde fois.
    }
  }

  static Future<void> pause() async {
    _player?.pause();
    state.value = state.value.copyWith(isPlaying: false);
  }

  static Future<void> resume() async {
    try {
      await _player?.play();
    } catch (_) {}
    state.value = state.value.copyWith(isPlaying: true);
  }

  static Future<void> _stopInternal() async {
    await _playingSub?.cancel();
    await _pauseSub?.cancel();
    await _endedSub?.cancel();
    await _timeSub?.cancel();
    await _durSub?.cancel();
    _playingSub = null;
    _pauseSub = null;
    _endedSub = null;
    _timeSub = null;
    _durSub = null;
    _player?.pause();
    _player = null;
    _currentUrl = null;
    state.value = const AudioPlaybackState();
  }

  static Future<void> stop() => _stopInternal();

  static void dispose() {
    _stopInternal();
  }
}
