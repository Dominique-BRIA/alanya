import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_state.dart';

/// Lecteur audio réactif (mobile/desktop).
///
/// Expose [state], un [ValueNotifier<AudioPlaybackState>] que l'UI écoute via
/// [ValueListenableBuilder] pour afficher en temps réel l'icône play/pause et
/// la barre de progression.
///
/// - **Mobile (Android/iOS)** : [AudioPlayer] du paquet audioplayers, avec
///   suivi complet de l'état (play, pause, resume, position, durée).
/// - **Desktop (Linux/macOS/Windows)** : lecteur système externe (xdg-open…),
///   sans suivi réactif (comportement inchangé par rapport à l'ancien code).
class InlineAudioPlayer {
  static AudioPlayer? _player;
  static String? _currentUrl;
  static StreamSubscription<PlayerState>? _stateSub;
  static StreamSubscription<Duration>? _posSub;
  static StreamSubscription<Duration>? _durSub;
  static StreamSubscription<void>? _completeSub;

  /// Source unique de vérité pour l'UI. Singleton statique persistant.
  static final ValueNotifier<AudioPlaybackState> state =
      ValueNotifier(const AudioPlaybackState());

  /// Bascule play / pause pour une URL donnée :
  /// - cet audio joue déjà   → **pause** (garde le lecteur, ne redémarre pas).
  /// - cet audio est en pause → **reprend** là où il s'est arrêté.
  /// - un autre audio / rien  → **démarre** cet audio depuis le début.
  static Future<void> toggle(String url, {Duration? totalDuration}) async {
    if (_currentUrl == url && state.value.isPlaying) {
      await pause();
    } else if (_currentUrl == url) {
      await resume();
    } else {
      await play(url, totalDuration: totalDuration);
    }
  }

  /// Démarre la lecture d'une URL (interrompt tout audio en cours).
  static Future<void> play(String url, {Duration? totalDuration}) async {
    await _stopInternal();

    _currentUrl = url;
    state.value = AudioPlaybackState(
      url: url,
      isPlaying: false,
      position: Duration.zero,
      duration: totalDuration,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      _player = AudioPlayer();

      _stateSub = _player!.onPlayerStateChanged.listen((s) {
        state.value = state.value.copyWith(
          isPlaying: s == PlayerState.playing,
        );
      });

      _posSub = _player!.onPositionChanged.listen((pos) {
        state.value = state.value.copyWith(position: pos);
      });

      _durSub = _player!.onDurationChanged.listen((dur) {
        state.value = state.value.copyWith(duration: dur);
      });

      _completeSub = _player!.onPlayerComplete.listen((_) {
        _stopInternal();
      });

      await _player!.play(UrlSource(url));
    } else {
      // Desktop : lecteur système externe (pas de suivi d'état réactif).
      state.value = state.value.copyWith(isPlaying: true);
      try {
        if (Platform.isLinux) {
          await Process.run('xdg-open', [url]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [url]);
        } else if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', url]);
        }
      } catch (_) {}
    }
  }

  /// Met en pause (le lecteur est conservé, reprise possible via [resume]).
  static Future<void> pause() async {
    await _player?.pause();
    state.value = state.value.copyWith(isPlaying: false);
  }

  /// Reprend la lecture après une pause.
  static Future<void> resume() async {
    await _player?.resume();
    state.value = state.value.copyWith(isPlaying: true);
  }

  /// Arrêt complet : annule les subscriptions, libère le lecteur, réinitialise
  /// l'état. Appelé automatiquement à la fin de la lecture et par [stop].
  static Future<void> _stopInternal() async {
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _completeSub?.cancel();
    _stateSub = null;
    _posSub = null;
    _durSub = null;
    _completeSub = null;
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _currentUrl = null;
    state.value = const AudioPlaybackState();
  }

  /// API publique — rétro-compatible avec l'ancien appel `stop()` (était `void`).
  static Future<void> stop() => _stopInternal();

  static void dispose() {
    _stopInternal();
  }
}
