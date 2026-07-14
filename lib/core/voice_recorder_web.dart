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
      _recording = true;
      return true;
    } catch (_) {
      _cleanup();
      return false;
    }
  }

  Future<({Uint8List bytes, int durationMs})?> stop() async {
    if (!_recording || _recorder == null) return null;
    final started = _startedAt ?? DateTime.now();
    final completer = Completer<({Uint8List bytes, int durationMs})?>();

    void onStop(html.Event _) async {
      try {
        final blob = html.Blob(_chunks, "audio/webm");
        final reader = html.FileReader();
        reader.onLoadEnd.listen((_) {
          final result = reader.result;
          if (result is ByteBuffer) {
            final durationMs = DateTime.now().difference(started).inMilliseconds;
            completer.complete((bytes: result.asUint8List(), durationMs: durationMs));
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
    for (final track in _stream?.getAudioTracks() ?? <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
  }
}
