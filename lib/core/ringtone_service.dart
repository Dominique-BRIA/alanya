import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service dédié aux sonneries d'appel (outgoing/incoming).
///
/// Découplé de [InlineAudioPlayer] pour deux raisons :
///  1. On ne veut PAS que déclencher une sonnerie d'appel interrompe la lecture
///     d'un message vocal (ou vice-versa).
///  2. Les sonneries d'appel ont un contexte audio spécifique : loop actif,
///     volume à fond, et sur Android on veut le "flux voix" plutôt que le
///     "flux média" (le volume physique du téléphone contrôle alors la
///     sonnerie comme sur un vrai appel).
///
/// Utilisation :
/// ```dart
/// await RingtoneService.instance.startOutgoing(); // appel sortant, "bip bip"
/// await RingtoneService.instance.startIncoming(); // appel entrant, "dring dring"
/// await RingtoneService.instance.stop();          // à l'acceptation/refus/fin
/// ```
class RingtoneService {
  RingtoneService._();
  static final RingtoneService instance = RingtoneService._();

  AudioPlayer? _player;
  String? _currentAsset;

  static const _outgoingAsset = "sounds/outgoing_ring.mp3";
  static const _incomingAsset = "sounds/incoming_ring.mp3";

  Future<void> startOutgoing() => _play(_outgoingAsset);

  Future<void> startIncoming() => _play(_incomingAsset);

  Future<void> _play(String asset) async {
    // Si on rejoue le même son (ex: 2 events consécutifs), on ne relance pas.
    if (_currentAsset == asset && _player != null) return;

    await stop();

    try {
      final p = AudioPlayer();
      // AudioContext : sur Android, on force le stream "voice call" pour que
      // la sonnerie soit audible même quand le mode "silencieux médias" est
      // actif, et pour qu'elle sorte sur haut-parleur (routing appel).
      await p.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.duckOthers,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      await p.play(AssetSource(asset));
      _player = p;
      _currentAsset = asset;
      debugPrint("[RingtoneService] ▶️ $asset (loop)");
    } catch (e) {
      debugPrint("[RingtoneService] ❌ échec play $asset: $e");
      _player = null;
      _currentAsset = null;
    }
  }

  Future<void> stop() async {
    final p = _player;
    if (p == null) return;
    _player = null;
    _currentAsset = null;
    try {
      await p.stop();
      await p.release();
      await p.dispose();
      debugPrint("[RingtoneService] ⏹️ stop");
    } catch (_) {}
  }
}
