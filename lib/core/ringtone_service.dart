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

  // Lecteur séparé pour les sons courts (message reçu) afin de ne jamais
  // perturber la sonnerie d'appel (_player).
  AudioPlayer? _cuePlayer;
  DateTime? _lastMessageCueAt;

  static const _outgoingAsset = "sounds/outgoing_ring.mp3";
  static const _incomingAsset = "sounds/incoming_ring.mp3";
  static const _cueAsset = "sounds/notification.mp3";

  /// Anti-rafale : plusieurs messages reçus coup sur coup ne produisent qu'un
  /// son. Le verrou vit ici, et non chez les appelants, pour que la
  /// conversation ouverte et le reste de l'app ne puissent pas sonner deux
  /// fois pour un même message.
  static const _messageCueGap = Duration(milliseconds: 1500);

  Future<void> startOutgoing() => _play(_outgoingAsset);

  Future<void> startIncoming() => _play(_incomingAsset);

  /// Son bref signalant l'**arrivée d'un message** (one-shot, non bloquant,
  /// échec silencieux).
  ///
  /// Ce son portait auparavant l'apparition de l'indicateur « en train
  /// d'écrire » : le destinataire l'entendait pendant que l'expéditeur tapait,
  /// donc avant que le message existe, et n'entendait rien à sa réception.
  /// Il ne marque désormais que la réception.
  Future<void> playMessageReceived() async {
    final now = DateTime.now();
    if (_lastMessageCueAt != null &&
        now.difference(_lastMessageCueAt!) < _messageCueGap) {
      return;
    }
    _lastMessageCueAt = now;
    try {
      final p = _cuePlayer ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      // Volume plein : c'est une notification, le volume physique du téléphone
      // reste maître. L'ancien 0.22 convenait à un son d'ambiance, pas à un
      // événement que l'utilisateur doit remarquer.
      await p.setVolume(1.0);
      await p.stop();
      await p.play(AssetSource(_cueAsset));
    } catch (_) {}
  }

  /// Ton bref joué quand un participant **rejoint** une réunion (style Google
  /// Meet). One-shot, en échec silencieux.
  Future<void> playParticipantJoined() => _playCueOnce();

  /// Ton bref joué quand un participant **quitte** une réunion. Même son que
  /// pour l'arrivée, on évite d'ajouter un asset.
  Future<void> playParticipantLeft() => _playCueOnce(volume: 0.6);

  /// Alerte de fin de réunion : le même son que les autres repères, mais joué
  /// **deux fois**.
  ///
  /// Le doublement est ce qui la distingue à l'oreille d'une arrivée ou d'un
  /// départ de participant, sans ajouter d'asset. Elle contourne volontairement
  /// l'anti-rafale de [_playCueOnce] — c'est justement une rafale de deux — mais
  /// remet son horodatage à jour pour ne pas se superposer à un son voisin.
  Future<void> playAlerteReunion() async {
    _lastCueAt = DateTime.now();
    try {
      final p = _cuePlayer ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(1.0);
      await p.stop();
      await p.play(AssetSource(_cueAsset));
      await Future<void>.delayed(const Duration(milliseconds: 850));
      await p.stop();
      await p.play(AssetSource(_cueAsset));
    } catch (_) {}
  }

  /// Joue le son de notification une seule fois, avec anti-rafale léger.
  Future<void> _playCueOnce({double volume = 1.0}) async {
    final now = DateTime.now();
    if (_lastCueAt != null && now.difference(_lastCueAt!) < _cueGap) return;
    _lastCueAt = now;
    try {
      final p = _cuePlayer ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(volume);
      await p.stop();
      await p.play(AssetSource(_cueAsset));
    } catch (_) {}
  }

  DateTime? _lastCueAt;
  static const _cueGap = Duration(milliseconds: 700);

  // ── Centre d'appels (standard) ───────────────────────────────────────────
  //
  // Lecteur DISTINCT de `_player` : l'invite vocale remplace le bip d'attente
  // sortant, mais les deux ne doivent pas se disputer le même objet — couper
  // l'un couperait l'autre au mauvais moment. Distinct de `_cuePlayer`
  // également, dont le rôle est de jouer des sons courts par-dessus tout.
  AudioPlayer? _ivrPlayer;

  /// Invite vocale du standard : « tapez 1 pour… ». Une seule fois.
  Future<void> playIvrPrompt(String url) => _playIvr(url, loop: false);

  /// Musique d'attente pendant que l'agent sonne. En boucle.
  Future<void> playIvrHold(String url) => _playIvr(url, loop: true);

  /// Coupe l'audio du standard, sans toucher aux sonneries d'appel.
  Future<void> stopIvr() async {
    final p = _ivrPlayer;
    if (p == null) return;
    _ivrPlayer = null;
    try {
      await p.stop();
      await p.release();
      await p.dispose();
    } catch (_) {}
  }

  Future<void> _playIvr(String url, {required bool loop}) async {
    await stopIvr();
    try {
      final p = AudioPlayer();
      // Même contexte que les sonneries : flux voix sur Android, pour que le
      // standard s'entende comme un appel et non comme un média — le volume
      // physique du téléphone le règle alors, et le mode silencieux médias ne
      // le fait pas taire.
      await p.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await p.setVolume(1.0);
      // `UrlSource` et non `AssetSource` : les sons du standard sont servis par
      // le serveur, hors authentification, et changent d'un centre à l'autre.
      await p.play(UrlSource(url));
      _ivrPlayer = p;
      debugPrint("[RingtoneService] ▶️ standard $url (loop=$loop)");
    } catch (e) {
      // Échec silencieux : l'écran du standard affiche les options, il reste
      // parfaitement utilisable sans le son.
      debugPrint("[RingtoneService] ❌ échec standard $url: $e");
      _ivrPlayer = null;
    }
  }

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
