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

  /// Tonalité d'attente d'un appel SORTANT.
  ///
  /// ⚠️ [hautParleur] est passé par l'appelant, et vaut faux par défaut : sur un
  /// appel sortant, le téléphone est déjà à l'oreille. Ce son partageait le
  /// contexte de la sonnerie entrante, donc `isSpeakerphoneOn: true` : le
  /// « bip bip » partait au haut-parleur, fort, pendant que l'écran affichait
  /// « écouteur ». Un appel VIDÉO, lui, passe `true` — la route doit suivre ce
  /// que l'écran annonce, dans les deux sens.
  Future<void> startOutgoing({bool hautParleur = false}) =>
      _play(_outgoingAsset, hautParleur: hautParleur);

  /// Sonnerie d'un appel ENTRANT — toujours au haut-parleur : le téléphone est
  /// dans une poche ou sur une table, il faut l'entendre.
  ///
  /// [url] est la sonnerie propre à une LISTE DE CONTACTS, déjà rendue jouable
  /// (base + jeton) par `SonneriesDeListes`. Absente ou injouable, on retombe
  /// sur l'asset embarqué : une sonnerie personnalisée qui ne se télécharge pas
  /// ne doit jamais produire un appel silencieux.
  Future<void> startIncoming({String? url}) {
    if (url == null || url.isEmpty) {
      return _play(_incomingAsset, hautParleur: true);
    }
    return _playUrl(url, hautParleur: true);
  }

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

      /*
       * 🔴 ON NE TÉLÉCHARGE PLUS AVANT DE JOUER — correction du 18/08/2026.
       *
       * Le user : « très souvent, dès le premier appel, le vocal ne se met pas
       * à chanter ». Le mot qui compte est PREMIER, et il désignait le cache.
       *
       * Ce code attendait les 256 Ko du fichier complet avant la première note,
       * avec 8 secondes de patience. Au premier appel, le cache est vide : il y
       * avait donc un silence long, puis un repli sur `UrlSource` — c'est-à-dire
       * sur le streaming qu'il aurait fallu faire d'emblée, mais huit secondes
       * trop tard. Aux appels suivants le fichier était sur le disque et
       * démarrait instantanément, ce qui explique exactement le « premier ».
       *
       * Pire, l'attente se transformait en silence DÉFINITIF : l'appelant qui
       * n'entend rien tape une touche, `stopIvr()` change la génération, et le
       * téléchargement qui s'achève est jeté. L'invite n'aura jamais joué.
       *
       * L'optimisation inversait donc ce qu'elle cherchait à améliorer. On rend
       * la source réseau IMMÉDIATEMENT — la lecture commence dès les premiers
       * octets — et on remplit le cache EN ARRIÈRE-PLAN pour la fois suivante.
       * Les deux cas y gagnent : le premier appel démarre tout de suite, les
       * suivants lisent le disque.
       */
      unawaited(_remplirCache(url, file));
    } catch (e) {
      debugPrint("[RingtoneService] cache indisponible pour $url : $e");
    }
    return UrlSource(url);
  }

  /// Télécharge le son pour la PROCHAINE lecture. N'est jamais attendu.
  ///
  /// ⚠️ Écrit dans un fichier temporaire puis renomme : une écriture
  /// interrompue — application tuée, disque plein — laisserait sinon un fichier
  /// tronqué que `_resoudreSourceIvr` prendrait pour un cache valide, et le son
  /// serait coupé à chaque appel suivant sans que rien ne l'explique.
  Future<void> _remplirCache(String url, File destination) async {
    try {
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return;
      final partiel = File('${destination.path}.part');
      await partiel.writeAsBytes(r.bodyBytes, flush: true);
      await partiel.rename(destination.path);
    } catch (_) {
      // Sans conséquence : la lecture en cours passe par le réseau, et la
      // prochaine retentera.
    }
  }

  /// Le son du standard sort-il par le HAUT-PARLEUR ?
  ///
  /// 🔴 CE DRAPEAU EXISTE PARCE QUE `Helper.setSpeakerphoneOn` NE SUFFIT PAS.
  /// Cette fonction route la session **WebRTC** ; or l'audio d'un standard est
  /// joué par `audioplayers`, avec son propre contexte. Tant que celui-ci
  /// forçait `isSpeakerphoneOn: true` en dur, couper le haut-parleur pendant un
  /// appel de centre ne changeait strictement rien — la bascule agissait sur un
  /// flux qui ne jouait rien (signalé par le user le 18/08/2026).
  ///
  /// Même famille que le défaut du 12/08 : quand un son se comporte mal, la
  /// question n'est pas ce qu'il contient, c'est PAR OÙ il sort.
  bool _hautParleurIvr = true;

  /// Bascule la sortie du son du standard, et l'applique à la lecture EN COURS.
  ///
  /// ⚠️ Le contexte est reposé **puis la lecture est relancée**. Android ne
  /// réoriente pas un flux déjà démarré sur un simple changement de contexte :
  /// sans reprise, le réglage ne prendrait qu'au son suivant, c'est-à-dire
  /// jamais du point de vue de quelqu'un qui écoute une invite en boucle.
  Future<void> reglerHautParleurIvr(bool actif) async {
    if (_hautParleurIvr == actif) return;
    _hautParleurIvr = actif;
    final url = _urlIvrEnCours;
    if (url == null) return;
    await _playIvr(url, loop: _loopIvrEnCours);
  }

  /// La lecture en cours, pour pouvoir la reprendre sur l'autre sortie.
  String? _urlIvrEnCours;
  bool _loopIvrEnCours = true;

  /// Oublie l'état du standard — à appeler à la FIN d'un appel, jamais entre
  /// deux sons du même appel.
  ///
  /// ⚠️ Sans elle, `_hautParleurIvr` survivait d'un appel à l'autre. En
  /// pratique le défaut se rattrapait tout seul, l'ouverture d'un menu forçant
  /// le haut-parleur ; mais c'était une correction accidentelle, pas une
  /// garantie, et elle aurait disparu au premier standard qui n'appelle pas
  /// `_hautParleurPourStandard`.
  ///
  /// Volontairement séparée de [stopIvr], qui est appelée à CHAQUE appui sur une
  /// touche : y remettre le drapeau annulerait le choix de l'appelant dès qu'il
  /// change de son.
  void reinitialiserIvr() {
    _hautParleurIvr = true;
    _urlIvrEnCours = null;
    _loopIvrEnCours = true;
  }

  /// Le contexte audio du standard, selon la sortie choisie.
  ///
  /// ⚠️ LES DEUX SORTIES NE DIFFÈRENT PAS QUE PAR UN BOOLÉEN. Le type d'usage
  /// commande le routage sous Android : `media`/`music` sort au haut-parleur,
  /// `voiceCommunication`/`speech` à l'écouteur. Ne changer que
  /// `isSpeakerphoneOn` laisserait le son sortir au mauvais endroit — c'est
  /// exactement ce qui avait fait croire à un problème de format le 12/08/2026,
  /// où trois causes plausibles ont été avancées avant de constater que le son
  /// sortait par l'écouteur.
  AudioContext _contexteIvr() {
    if (_hautParleurIvr) {
      return AudioContext(
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
      );
    }
    return AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.voiceCommunication,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    );
  }

  Future<void> _playIvr(String url,
      {required bool loop, void Function()? onComplete}) async {
    await stopIvr();
    final gen = _generationIvr;
    try {
      // Mémorisé AVANT la lecture : c'est ce qui permet de reprendre le même
      // son sur l'autre sortie quand l'appelant bascule le haut-parleur.
      _urlIvrEnCours = url;
      _loopIvrEnCours = loop;

      final p = AudioPlayer();
      await p.setAudioContext(_contexteIvr());
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

  /// Contexte audio d'une sonnerie d'appel, partagé par l'asset et l'URL.
  ///
  /// Sur Android, on force le flux « appel » pour que la sonnerie reste audible
  /// quand le mode « silencieux médias » est actif, et pour qu'elle sorte au
  /// haut-parleur. ⚠️ **Le type d'usage commande le routage, pas seulement le
  /// booléen** — même règle que pour l'audio du standard : `notificationRingtone`
  /// sort au haut-parleur, `voiceCommunication` à l'écouteur.
  AudioContext _contexteSonnerie(bool hautParleur) => AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: hautParleur,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: hautParleur
              ? AndroidUsageType.notificationRingtone
              : AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );

  Future<void> _play(String asset, {required bool hautParleur}) async {
    // Si on rejoue le même son (ex: 2 events consécutifs), on ne relance pas.
    if (_currentAsset == asset && _player != null) return;

    await stop();
    // Retenu APRÈS l'arrêt, qui vient lui-même d'incrémenter le compteur : tout
    // `stop()` ultérieur rendra donc cette valeur périmée.
    final gen = _generation;

    try {
      final p = AudioPlayer();
      await p.setAudioContext(_contexteSonnerie(hautParleur));
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

  /// Même chose que [_play], mais depuis une URL distante.
  ///
  /// ⚠️ Il ne suffisait PAS de remplacer `AssetSource` par `UrlSource` : une
  /// source distante ajoute un chargement réseau au milieu des quatre allers-
  /// retours natifs, donc une fenêtre bien plus large pour que le décrochage
  /// arrive avant le début de la lecture. Le compteur de génération est vérifié
  /// aux mêmes endroits, et un échec retombe sur l'asset — sans ce repli, une
  /// sonnerie de liste injoignable rendrait l'appel muet.
  Future<void> _playUrl(String url, {required bool hautParleur}) async {
    if (_currentAsset == url && _player != null) return;

    await stop();
    final gen = _generation;

    try {
      final p = AudioPlayer();
      await p.setAudioContext(_contexteSonnerie(hautParleur));
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      if (gen != _generation) return _jeter(p);
      await p.play(UrlSource(url));
      if (gen != _generation) return _jeter(p);
      _player = p;
      _currentAsset = url;
      debugPrint("[RingtoneService] ▶️ ${_finDe(url)} (liste, loop)");
    } catch (e) {
      debugPrint("[RingtoneService] ❌ sonnerie de liste ${_finDe(url)}: $e");
      _player = null;
      _currentAsset = null;
      // L'arrêt qui a pu survenir pendant l'échec doit rester prioritaire :
      // sans ce contrôle, le repli relancerait une sonnerie déjà annulée.
      if (gen == _generation) {
        await _play(_incomingAsset, hautParleur: hautParleur);
      }
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
