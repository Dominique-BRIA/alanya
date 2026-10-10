// ignore: deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Enregistrement vocal via l'API MediaRecorder du navigateur (web uniquement).
class VoiceRecorder {
  html.MediaRecorder? _recorder;
  html.MediaStream? _stream;
  final List<html.Blob> _chunks = [];
  DateTime? _startedAt;
  bool _recording = false;

  bool get isSupported => true;

  /// Cumul des segments déjà enregistrés, pauses exclues — voir la version
  /// native, dont ce fichier doit exposer la MÊME surface : les deux sont
  /// choisies à la compilation, un membre manquant ici ne casserait que le
  /// build web, et bien plus tard.
  Duration _cumul = Duration.zero;

  bool get enCours => _recording;
  bool get enPause => _recording && _startedAt == null;

  Duration get duree {
    final debut = _startedAt;
    return debut == null ? _cumul : _cumul + DateTime.now().difference(debut);
  }

  Future<bool> pause() async {
    if (!_recording || _startedAt == null || _recorder == null) return false;
    _cumul += DateTime.now().difference(_startedAt!);
    _startedAt = null;
    try {
      _recorder!.pause();
      return true;
    } catch (_) {
      _startedAt = DateTime.now();
      return false;
    }
  }

  Future<bool> resume() async {
    if (!_recording || _startedAt != null || _recorder == null) return false;
    try {
      _recorder!.resume();
      _startedAt = DateTime.now();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> start() async {
    if (_recording) return true;
    try {
      final stream = await html.window.navigator.mediaDevices?.getUserMedia({"audio": true});
      if (stream == null) return false;
      _stream = stream;
      _chunks.clear();
      _recorder = html.MediaRecorder(stream, {"mimeType": "audio/webm"});
      _recorder!.addEventListener("dataavailable", (event) {
        final blob = (event as dynamic).data as html.Blob?;
        if (blob != null && blob.size > 0) _chunks.add(blob);
      });
      _recorder!.start();
      _startedAt = DateTime.now();
      _cumul = Duration.zero;
      _recording = true;
      return true;
    } catch (_) {
      _cleanup();
      return false;
    }
  }

  Future<({Uint8List bytes, int durationMs})?> stop() async {
    if (!_recording || _recorder == null) return null;
    // Fermé AVANT l'arrêt natif, comme côté io : la durée envoyée doit être
    // celle qu'affichait le minuteur, pauses exclues.
    final dureeFinale = duree;
    final completer = Completer<({Uint8List bytes, int durationMs})?>();

    void onStop(html.Event _) async {
      try {
        final blob = html.Blob(_chunks, "audio/webm");
        final reader = html.FileReader();
        reader.onLoadEnd.listen((_) {
          final result = reader.result;
          if (result is ByteBuffer) {
            completer.complete((
              bytes: result.asUint8List(),
              durationMs: dureeFinale.inMilliseconds,
            ));
          } else {
            completer.complete(null);
          }
          _cleanup();
        });
        reader.readAsArrayBuffer(blob);
      } catch (_) {
        completer.complete(null);
        _cleanup();
      }
    }

    _recorder!.addEventListener("stop", onStop);
    _recorder!.stop();
    _recording = false;
    return completer.future;
  }

  void cancel() {
    if (_recorder != null && _recording) {
      try {
        _recorder!.stop();
      } catch (_) {}
    }
    _cleanup();
  }

  void _cleanup() {
    _recording = false;
    _chunks.clear();
    _recorder = null;
    _startedAt = null;
    // Sans cette remise, le cumul d'un enregistrement abandonné s'ajouterait au
    // suivant : le minuteur repartirait de la durée du précédent.
    _cumul = Duration.zero;
    for (final track in _stream?.getAudioTracks() ?? <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
  }
}
