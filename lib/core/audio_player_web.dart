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
    // Élément gardé dans une variable LOCALE non nullable, en plus du champ.
    // Le champ `_player` est nullable — il est remis à nul à l'arrêt — et
    // l'analyseur refusait donc d'y accéder directement, ce qui laissait six
    // erreurs dans ce fichier. Elles ne se voyaient pas au build : cette
    // implémentation n'est sélectionnée que sur le web, par l'export
    // conditionnel de `audio_player.dart`, et le projet ne cible qu'Android.
    // ignore: deprecated_member_use
    final lecteur = html.AudioElement()..src = url;
    _player = lecteur;

    state.value = AudioPlaybackState(
      url: url,
      isPlaying: false,
      position: Duration.zero,
      duration: totalDuration,
    );

    _playingSub = lecteur.onPlaying.listen((_) {
      state.value = state.value.copyWith(isPlaying: true);
    });

    _pauseSub = lecteur.onPause.listen((_) {
      state.value = state.value.copyWith(isPlaying: false);
    });

    _endedSub = lecteur.onEnded.listen((_) {
      _stopInternal();
    });

    _timeSub = lecteur.onTimeUpdate.listen((_) {
      final p = _player;
      if (p == null) return;
      state.value = state.value.copyWith(
        position: Duration(milliseconds: (p.currentTime * 1000).round()),
      );
    });

    _durSub = lecteur.onDurationChange.listen((_) {
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
      await lecteur.play();
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
