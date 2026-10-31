import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/plafond_media.dart';
import '../../../core/voice_recorder.dart';
import '../../../l10n/app_localizations.dart';
import '../screens/editeur_media_statut_screen.dart' show MediaEdite;
import '../screens/status_viewer_screen.dart' show dureeVideoStatutMax;

/// STATUT AUDIO (01/11/2026, repris d'Alanya) : enregistrer au micro, ou
/// choisir un fichier audio, puis publier.
///
/// Même plafond que la vidéo ([dureeVideoStatutMax]) : la visionneuse ne lit
/// pas au-delà, et un enregistrement s'arrête de lui-même à la limite.
///
/// Rend le média prêt à publier (comme l'éditeur d'une photo), ou `null`.
class FeuilleStatutAudio extends StatefulWidget {
  const FeuilleStatutAudio({super.key});

  static Future<MediaEdite?> ouvrir(BuildContext context) =>
      showModalBottomSheet<MediaEdite>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const FeuilleStatutAudio(),
      );

  @override
  State<FeuilleStatutAudio> createState() => _FeuilleStatutAudioState();
}

typedef _AudioPret = ({Uint8List octets, int dureeMs, String nom, String mime});

class _FeuilleStatutAudioState extends State<FeuilleStatutAudio> {
  final _micro = VoiceRecorder();
  Timer? _tic;
  bool _enregistre = false;
  _AudioPret? _pret;

  @override
  void dispose() {
    _tic?.cancel();
    if (_enregistre) _micro.cancel();
    super.dispose();
  }

  Future<void> _basculer() async {
    if (_enregistre) {
      await _arreter();
      return;
    }
    if (!await _micro.start()) {
      if (mounted) showAppSnackBar(tr(context, 'status_mic_denied'));
      return;
    }
    setState(() {
      _enregistre = true;
      _pret = null;
    });
    _tic = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_micro.duree >= dureeVideoStatutMax) {
        unawaited(_arreter());
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _arreter() async {
    _tic?.cancel();
    final r = await _micro.stop();
    if (!mounted) return;
    setState(() {
      _enregistre = false;
      if (r != null) {
        _pret = (
          octets: r.bytes,
          dureeMs: r.durationMs,
          nom: 'statut-audio.m4a',
          mime: 'audio/mp4',
        );
      }
    });
  }

  static String _mimeDe(String nom) {
    final ext = nom.toLowerCase().split('.').last;
    return switch (ext) {
      'm4a' || 'aac' || 'mp4' => 'audio/mp4',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      _ => 'audio/mpeg',
    };
  }

  /// La durée d'un fichier, lue par le lecteur — elle ne figure pas dans ce
  /// que rend le sélecteur.
  static Future<int> _dureeDe(String chemin) async {
    final c = VideoPlayerController.file(File(chemin));
    try {
      await c.initialize();
      return c.value.duration.inMilliseconds;
    } catch (_) {
      return 0;
    } finally {
      await c.dispose();
    }
  }

  Future<void> _choisirFichier() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: false);
    final f = r?.files.single;
    final chemin = f?.path;
    if (f == null || chemin == null || !mounted) return;
    if (depassePlafondMedia(f.size)) {
      showAppSnackBar(messageMediasEcartes([f.name], context: context) ?? '');
      return;
    }
    final dureeMs = await _dureeDe(chemin);
    if (!mounted) return;
    if (dureeMs > dureeVideoStatutMax.inMilliseconds) {
      showAppSnackBar(tr(context, 'status_audio_too_long',
          {'n': '${dureeVideoStatutMax.inSeconds}'}));
      return;
    }
    final octets = await File(chemin).readAsBytes();
    if (!mounted || octets.isEmpty) return;
    setState(() => _pret = (
          octets: octets,
          dureeMs: dureeMs,
          nom: f.name,
          mime: _mimeDe(f.name),
        ));
  }

  void _publier() {
    final p = _pret;
    if (p == null) return;
    Navigator.of(context).pop(MediaEdite(
      octets: p.octets,
      nomFichier: p.nom,
      mimeType: p.mime,
      chemin: null,
      durationMs: p.dureeMs,
    ));
  }

  static String _duree(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final couleur = Theme.of(context).colorScheme.primary;
    final p = _pret;
    final temps = _enregistre
        ? _micro.duree
        : Duration(milliseconds: p?.dureeMs ?? 0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'status_audio_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _basculer,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _enregistre ? Colors.redAccent : couleur,
              ),
              child: Icon(_enregistre ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _enregistre || p != null
                ? '${_duree(temps)} / ${_duree(dureeVideoStatutMax)}'
                : tr(context, 'status_audio_record'),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 18),
          if (p != null && !_enregistre)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: () => setState(() => _pret = null),
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'status_audio_redo')),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _publier,
                icon: const Icon(Icons.send),
                label: Text(tr(context, 'status_audio_publish')),
              ),
            ])
          else if (!_enregistre)
            TextButton.icon(
              onPressed: _choisirFichier,
              icon: const Icon(Icons.library_music_outlined),
              label: Text(tr(context, 'status_audio_pick')),
            ),
        ]),
      ),
    );
  }
}
