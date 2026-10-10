import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Enregistrement vocal natif Android / iOS (package `record`).
/// Desktop Linux/macOS/Windows : non supporté (utiliser 📎).
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  /// Début du segment EN COURS, ou `null` quand l'enregistrement est en pause.
  DateTime? _debutSegment;

  /// Durée des segments DÉJÀ enregistrés, pauses exclues.
  ///
  /// 🔴 SANS CE CUMUL, LA PAUSE MENTIRAIT. La durée se calculait sur l'écart
  /// entre le premier `start()` et le `stop()` — un temps de mur, qui compte
  /// les pauses. Un enregistrement de 10 s mis en pause 2 minutes serait annoncé
  /// à 2 min 10, et la barre de progression du lecteur, comme la durée envoyée
  /// au serveur, seraient fausses. On additionne donc les segments joués.
  Duration _cumul = Duration.zero;

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Enregistre-t-on, pause comprise ?
  bool get enCours => _path != null;

  /// Est-on en pause ? Faux hors de tout enregistrement.
  bool get enPause => _path != null && _debutSegment == null;

  /// Durée réellement enregistrée à cet instant, pauses exclues.
  ///
  /// Lue par le minuteur de l'écran : c'est la MÊME mesure que celle qui partira
  /// au serveur, donc l'utilisateur ne peut pas voir un chiffre et en envoyer un
  /// autre.
  Duration get duree {
    final debut = _debutSegment;
    return debut == null ? _cumul : _cumul + DateTime.now().difference(debut);
  }

  Future<bool> start() async {
    if (!isSupported) return false;
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = "${dir.path}/alanya-voice-${DateTime.now().millisecondsSinceEpoch}.m4a";
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: _path!,
    );
    _debutSegment = DateTime.now();
    _cumul = Duration.zero;
    return true;
  }

  /// Suspend l'enregistrement sans clore le fichier.
  ///
  /// ⚠️ Le cumul est arrêté AVANT l'appel natif : `pause()` prend quelques
  /// millisecondes, et les compter dans le segment gonflerait la durée d'autant
  /// à chaque pause. L'écart est minime une fois, visible au bout de dix.
  Future<bool> pause() async {
    if (_path == null || _debutSegment == null) return false;
    _cumul += DateTime.now().difference(_debutSegment!);
    _debutSegment = null;
    try {
      await _recorder.pause();
      return true;
    } catch (_) {
      // Le natif a refusé : on RÉTABLIT le segment, sinon l'enregistrement
      // continuerait pendant que le minuteur, lui, resterait figé.
      _debutSegment = DateTime.now();
      return false;
    }
  }

  Future<bool> resume() async {
    if (_path == null || _debutSegment != null) return false;
    try {
      await _recorder.resume();
      _debutSegment = DateTime.now();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<({Uint8List bytes, int durationMs})?> stop() async {
    if (_path == null) return null;
    // Ferme le segment en cours AVANT l'arrêt natif, pour la même raison qu'à
    // la pause.
    final dureeFinale = duree;
    final path = await _recorder.stop();
    final filePath = path ?? _path!;
    _path = null;
    _debutSegment = null;
    _cumul = Duration.zero;
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.isEmpty) return null;
    return (bytes: bytes, durationMs: dureeFinale.inMilliseconds);
  }

  void cancel() {
    _recorder.stop();
    if (_path != null) {
      try {
        File(_path!).deleteSync();
      } catch (_) {}
    }
    _path = null;
    _debutSegment = null;
    _cumul = Duration.zero;
  }
}
