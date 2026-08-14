import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_overlay.dart';

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

  /// Génération de la sonnerie en cours.
  ///
  /// ⚠️ CE COMPTEUR CORRIGE UNE SONNERIE QUI NE S'ARRÊTAIT PLUS APRÈS LE
  /// DÉCROCHAGE, de façon intermittente.
  ///
  /// Démarrer une sonnerie demande quatre allers-retours vers la couche audio
  /// native — contexte, mode de boucle, volume, puis lecture — soit largement de
  /// quoi laisser passer un événement. Or les deux démarrages sont lancés SANS
  /// `await` (`startOutgoing` à la création de l'appel, `startIncoming` à
  /// l'arrivée), pendant que tous les arrêts, eux, sont attendus.
  ///
  /// Quand le décrochage tombe dans cette fenêtre, l'ordre réel devient :
  /// `stop()` s'exécute alors que `_player` est encore nul — il ne coupe donc
  /// RIEN — puis la préparation s'achève et la lecture démarre, en boucle, sans
  /// plus personne pour l'arrêter. D'où le « parfois » : la fenêtre est courte,
  /// mais elle s'allonge sur une couche audio froide.
  ///
  /// Le compteur transforme l'arrêt en intention : `stop()` l'incrémente, et
  /// toute lecture qui se réveille sur une génération périmée se jette au lieu
  /// de se lancer.
  int _generation = 0;

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

  /// Même rôle que [_generation], pour l'audio du standard : l'invite est lancée
  /// sans attente à l'arrivée du menu, et coupée dès l'appui sur une touche.
  /// Une touche tapée sans hésiter tombe donc dans la même fenêtre, et l'invite
  /// se serait mise à jouer sous la musique d'attente.
  int _generationIvr = 0;

  /// Invite vocale du standard : « tapez 1 pour… ». En boucle par défaut.
  Future<void> playIvrPrompt(String url, {bool loop = true}) =>
      _playIvr(url, loop: loop);

  /// Musique d'attente pendant que l'agent sonne. En boucle.
  Future<void> playIvrHold(String url, {bool loop = true}) =>
      _playIvr(url, loop: loop);

  /// Musiques de la file d'attente (`vocal_attente`) quand tous les agents sont occupés. En boucle.
  Future<void> playIvrQueueList(List<String> urls, {bool loop = true}) async {
    if (urls.isEmpty) return;
    if (urls.length == 1) {
      await _playIvr(urls.first, loop: loop);
      return;
    }
    await _playIvrSequence(urls, 0, loop: loop);
  }

  Future<void> _playIvrSequence(List<String> urls, int index,
      {required bool loop}) async {
    if (urls.isEmpty) return;
    final i = index % urls.length;
    await _playIvr(urls[i], loop: false, onComplete: () {
      final gen = _generationIvr;
      int next = i + 1;
      if (next >= urls.length) {
        if (!loop) return;
        next = 0;
      }
      if (gen == _generationIvr) {
        unawaited(_playIvrSequence(urls, next, loop: loop));
      }
    });
  }

  /// Coupe l'audio du standard, sans toucher aux sonneries d'appel.
  /// Relais de bouclage — voir [_playIvr]. Annulé avec le lecteur qu'il surveille.
  StreamSubscription<void>? _finIvrSub;

  Future<void> stopIvr() async {
    // Avant le retour anticipé : annule aussi une lecture encore en préparation.
    _generationIvr++;
    // Avant tout le reste : un relais laissé vivant relancerait la lecture que
    // l'on est en train d'arrêter.
    _finIvrSub?.cancel();
    _finIvrSub = null;
    final p = _ivrPlayer;
    if (p == null) return;
    _ivrPlayer = null;
    try {
      await p.stop();
      await p.release();
      await p.dispose();
    } catch (_) {}
  }

  /// La fin d'une URL, pour que la trace tienne sur une ligne de l'overlay.
  /// Le nom de fichier suffit à identifier le vocal ou la musique en cause.
  static String _finDe(String url) {
    final morceaux = url.split('/');
    return morceaux.isEmpty ? url : morceaux.last;
  }

  /// Télécharge et met en cache localement le fichier audio si c'est une URL HTTP.
  /// En cas de problème ou délai, retombe sur UrlSource.
  Future<Source> _resoudreSourceIvr(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return UrlSource(url);
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final hashName = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final filename = hashName.length > 80
          ? hashName.substring(hashName.length - 80)
          : hashName;
      final file = File('${tempDir.path}/ivr_$filename.mp3');

      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size > 0) {
          return DeviceFileSource(file.path);
        }
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return DeviceFileSource(file.path);
      }
    } catch (e) {
      debugPrint("[RingtoneService] Cache fallback for $url: $e");
    }
    return UrlSource(url);
  }

  Future<void> _playIvr(String url,
      {required bool loop, void Function()? onComplete}) async {
    await stopIvr();
    final gen = _generationIvr;
    try {
      final p = AudioPlayer();
      // Configuration mains-libres & média robuste : force le haut-parleur principal
      // et empêche le basculement silencieux vers l'écouteur d'oreille sur Android/iOS.
      await p.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.duckOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ),
      );
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await p.setVolume(1.0);
      if (gen != _generationIvr) return _jeter(p);

      // Résolution source (Cache disque local + fallback URL)
      final source = await _resoudreSourceIvr(url);
      if (gen != _generationIvr) return _jeter(p);

      await p.play(source);
      if (loop) await p.setReleaseMode(ReleaseMode.loop);
      if (gen != _generationIvr) {
        traceAppel("IVR audio ANNULÉ pendant le chargement (loop=$loop)");
        return _jeter(p);
      }
      _ivrPlayer = p;

      // Auto-Healing & Watchdog Listener
      _finIvrSub?.cancel();
      _finIvrSub = p.onPlayerStateChanged.listen((state) async {
        if (gen != _generationIvr || _ivrPlayer != p) return;
        if (state == PlayerState.paused || state == PlayerState.stopped) {
          try {
            await p.resume();
          } catch (_) {}
        }
      });

      p.onPlayerComplete.listen((_) async {
        if (gen != _generationIvr || _ivrPlayer != p) return;
        if (loop) {
          try {
            await p.seek(Duration.zero);
            await p.resume();
            traceAppel("IVR audio ↻ relance de ${_finDe(url)}");
          } catch (_) {}
        } else if (onComplete != null) {
          onComplete();
        }
      });
      traceAppel("IVR audio ▶️ ${_finDe(url)} (loop=$loop)");
    } catch (e) {
      traceAppel("IVR audio ❌ ${_finDe(url)} : $e");
      _ivrPlayer = null;
    }
  }

  Future<void> _play(String asset) async {
    // Si on rejoue le même son (ex: 2 events consécutifs), on ne relance pas.
    if (_currentAsset == asset && _player != null) return;

    await stop();
    // Retenu APRÈS l'arrêt, qui vient lui-même d'incrémenter le compteur : tout
    // `stop()` ultérieur rendra donc cette valeur périmée.
    final gen = _generation;

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
      // Un arrêt est-il passé pendant la préparation ? Alors ce lecteur ne doit
      // jamais commencer : c'est ici que se jouait la sonnerie fantôme.
      if (gen != _generation) return _jeter(p);
      await p.play(AssetSource(asset));
      // Et pendant le démarrage lui-même, qui est le plus long des quatre.
      if (gen != _generation) return _jeter(p);
      _player = p;
      _currentAsset = asset;
      debugPrint("[RingtoneService] ▶️ $asset (loop)");
    } catch (e) {
      debugPrint("[RingtoneService] ❌ échec play $asset: $e");
      _player = null;
      _currentAsset = null;
    }
  }

  /// Abandonne un lecteur qu'un arrêt a rendu caduc pendant sa préparation.
  Future<void> _jeter(AudioPlayer p) async {
    try {
      await p.stop();
      await p.release();
      await p.dispose();
      debugPrint(
          "[RingtoneService] ⏹️ sonnerie abandonnée (arrêt pendant la préparation)");
    } catch (_) {}
  }

  Future<void> stop() async {
    // ⚠️ AVANT le retour anticipé, et c'est tout l'intérêt : un arrêt demandé
    // alors qu'aucun lecteur n'existe encore doit quand même annuler la lecture
    // qui est en train de se préparer. C'est exactement le cas du décrochage
    // qui arrive plus vite que le démarrage de la sonnerie.
    _generation++;
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
