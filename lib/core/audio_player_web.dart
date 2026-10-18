import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ── Vitesse et avance (18/10/2026, bulle vocale comme Talky) ──────────────

  /// Les vitesses proposées, dans l'ordre du bouton : 1× → 1,5× → 2× → 1×.
  static const vitesses = <double>[1.0, 1.5, 2.0];

  /// La vitesse des messages vocaux, gardée d'une écoute à l'autre — on
  /// accélère les vocaux d'une personne bavarde une fois, pas à chaque fois.
  static final ValueNotifier<double> vitesse = ValueNotifier(1.0);
  static const _cleVitesse = 'vitesse_vocaux';
  static bool _vitesseLue = false;

  static Future<void> _lireVitesse() async {
    if (_vitesseLue) return;
    _vitesseLue = true;
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(_cleVitesse);
      if (v != null && vitesses.contains(v)) vitesse.value = v;
    } catch (_) {}
  }

  /// Passe à la vitesse suivante, l'applique à l'écoute en cours, la garde.
  static Future<void> changerVitesse() async {
    final i = vitesses.indexOf(vitesse.value);
    vitesse.value = vitesses[(i + 1) % vitesses.length];
    _player?.playbackRate = vitesse.value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_cleVitesse, vitesse.value);
    } catch (_) {}
  }

  /// Avance (ou recule) l'écoute en cours à [position].
  static Future<void> seek(Duration position) async {
    final p = _player;
    if (p == null) return;
    p.currentTime = position.inMilliseconds / 1000;
    state.value = state.value.copyWith(position: position);
  }

  /// Web : pas de fichier local, la forme d'onde est déterministe.
  static Future<String?> fichierLocal(String url) async => url;

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
    await _lireVitesse();
    lecteur.playbackRate = vitesse.value;

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
