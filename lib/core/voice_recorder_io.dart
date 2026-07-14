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
  DateTime? _startedAt;

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<bool> start() async {
    if (!isSupported) return false;
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = "${dir.path}/alanya-voice-${DateTime.now().millisecondsSinceEpoch}.m4a";
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: _path!,
    );
    _startedAt = DateTime.now();
    return true;
  }

  Future<({Uint8List bytes, int durationMs})?> stop() async {
    if (_path == null) return null;
    final path = await _recorder.stop();
    final filePath = path ?? _path!;
    _path = null;
    final started = _startedAt ?? DateTime.now();
    _startedAt = null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.isEmpty) return null;
    return (bytes: bytes, durationMs: durationMs);
  }

  void cancel() {
    _recorder.stop();
    if (_path != null) {
      try {
        File(_path!).deleteSync();
      } catch (_) {}
    }
    _path = null;
    _startedAt = null;
  }
}
