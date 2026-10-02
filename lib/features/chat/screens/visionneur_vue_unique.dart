import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../../core/api_client.dart';
import '../../../core/ecran_protege.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/message.dart';
import '../chat_repository.dart';

/// LE VISIONNEUR D'UN MESSAGE À VUE UNIQUE — photo, vidéo ou vocal.
///
/// 🔴 RIEN NE TOUCHE LE DISQUE. Les visionneurs ordinaires passent par le
/// cache des médias (`MediaCache`, `downloadToCache`) pour ne jamais
/// retélécharger : ici ce serait garder pour toujours ce qu'on a promis de ne
/// montrer qu'une fois. La photo vit en mémoire et en est évincée à la
/// fermeture ; la vidéo et le vocal sont lus en flux.
///
/// ⚠️ LA CAPTURE D'ÉCRAN EST BLOQUÉE pendant l'affichage (Android,
/// `EcranProtege`), et rétablie à la fermeture.
///
/// [onOuvert] est appelé dès que le serveur a accepté l'ouverture : l'écran
/// de discussion marque alors la bulle « Ouverte » sans attendre la sonnette.
class VisionneurVueUnique extends StatefulWidget {
  const VisionneurVueUnique({
    super.key,
    required this.message,
    required this.chat,
    required this.baseUrl,
    required this.token,
    this.onOuvert,
  });

  final Message message;
  final VoidCallback? onOuvert;
  final ChatRepository chat;
  final String baseUrl;
  final String? token;

  static Future<void> ouvrir(
    BuildContext context, {
    required Message message,
    required ChatRepository chat,
    required String baseUrl,
    required String? token,
    VoidCallback? onOuvert,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VisionneurVueUnique(
        message: message,
        chat: chat,
        baseUrl: baseUrl,
        token: token,
        onOuvert: onOuvert,
      ),
    ),
  );

  @override
  State<VisionneurVueUnique> createState() => _VisionneurVueUniqueState();
}

class _VisionneurVueUniqueState extends State<VisionneurVueUnique> {
  bool _ouvert = false;
  String? _erreur;
  MessageMedia? _media;

  Uint8List? _octetsImage;
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  Duration _positionAudio = Duration.zero;
  Duration _dureeAudio = Duration.zero;
  bool _audioEnCours = false;
  final List<StreamSubscription<dynamic>> _abonnements = [];

  @override
  void initState() {
    super.initState();
    unawaited(EcranProtege.activer());
    unawaited(_ouvrir());
  }

  String _adresse(MessageMedia m) =>
      '${widget.baseUrl}${m.url}${widget.token != null ? '?token=${widget.token}' : ''}';

  Future<void> _ouvrir() async {
    try {
      final r = await widget.chat.ouvrirVueUnique(widget.message.id);
      if (!mounted) return;
      if (r.media.isEmpty) throw ApiException(410, 'EFFACEE', 'EFFACEE');
      final media = r.media.first;
      _ouvert = true;
      widget.onOuvert?.call();
      setState(() => _media = media);

      if (media.mimeType.startsWith('image/')) {
        final rep = await http.get(Uri.parse(_adresse(media)));
        if (rep.statusCode != 200) throw ApiException(rep.statusCode, 'HTTP');
        if (mounted) setState(() => _octetsImage = rep.bodyBytes);
      } else if (media.mimeType.startsWith('video/')) {
        final c = VideoPlayerController.networkUrl(Uri.parse(_adresse(media)));
        _video = c;
        await c.initialize();
        if (!mounted) return;
        setState(() {});
        await c.play();
      } else {
        final p = AudioPlayer();
        _audio = p;
        _abonnements
          ..add(
            p.onPositionChanged.listen((d) {
              if (mounted) setState(() => _positionAudio = d);
            }),
          )
          ..add(
            p.onDurationChanged.listen((d) {
              if (mounted) setState(() => _dureeAudio = d);
            }),
          )
          ..add(
            p.onPlayerStateChanged.listen((s) {
              if (mounted)
                setState(() => _audioEnCours = s == PlayerState.playing);
            }),
          );
        await p.play(UrlSource(_adresse(media)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _erreur = tr(
          context,
          e.code == 'DEJA_OUVERTE' || e.message == 'DEJA_OUVERTE'
              ? 'vu_deja'
              : 'vu_indisponible',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _erreur = tr(context, 'vu_indisponible'));
    }
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    _video?.dispose();
    _audio?.dispose();
    // L'image quitte le cache des images décodées : sans cela, elle pourrait
    // réapparaître le temps de la session sans repasser par le serveur.
    final octets = _octetsImage;
    if (octets != null) unawaited(MemoryImage(octets).evict());
    _octetsImage = null;
    unawaited(EcranProtege.desactiver());
    // Fermer clôt l'accès côté serveur, qui efface le fichier si tous ont vu.
    if (_ouvert) unawaited(widget.chat.fermerVueUnique(widget.message.id));
    super.dispose();
  }

  String _duree(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const PastilleVueUnique(taille: 22, couleur: Colors.white),
            const SizedBox(width: 10),
            Text(tr(context, 'vu_titre')),
          ],
        ),
      ),
      body: SafeArea(child: Center(child: _corps())),
    );
  }

  Widget _corps() {
    if (_erreur != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _erreur!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
      );
    }
    final media = _media;
    if (media == null)
      return const CircularProgressIndicator(color: Colors.white);

    if (media.mimeType.startsWith('image/')) {
      final octets = _octetsImage;
      if (octets == null)
        return const CircularProgressIndicator(color: Colors.white);
      return InteractiveViewer(
        maxScale: 4,
        // `gaplessPlayback` inutile, et pas de `cacheWidth` : on veut l'image
        // nette, et elle est évincée du cache à la fermeture.
        child: Image.memory(octets, fit: BoxFit.contain),
      );
    }

    if (media.mimeType.startsWith('video/')) {
      final c = _video;
      if (c == null || !c.value.isInitialized) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return GestureDetector(
        onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      );
    }

    // Vocal : un grand bouton, la progression, la durée.
    final total = _dureeAudio.inMilliseconds > 0
        ? _dureeAudio
        : Duration(milliseconds: media.durationMs ?? 0);
    final avance = total.inMilliseconds == 0
        ? 0.0
        : (_positionAudio.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 72,
            color: Colors.white,
            icon: Icon(
              _audioEnCours
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
            ),
            onPressed: () {
              final p = _audio;
              if (p == null) return;
              _audioEnCours ? p.pause() : p.resume();
            },
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: avance,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
          const SizedBox(height: 8),
          Text(
            '${_duree(_positionAudio)} / ${_duree(total)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Le « 1 » cerclé de pointillés, signe de la vue unique (comme WhatsApp).
class PastilleVueUnique extends StatelessWidget {
  const PastilleVueUnique({super.key, this.taille = 20, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: taille,
      height: taille,
      child: CustomPaint(
        painter: _CerclePointille(couleur),
        child: Center(
          child: Text(
            '1',
            style: TextStyle(
              color: couleur,
              fontSize: taille * 0.55,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CerclePointille extends CustomPainter {
  _CerclePointille(this.couleur);
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    const segments = 8;
    const vide = 0.35; // part de chaque segment laissée vide
    for (var i = 0; i < segments; i++) {
      final debut = i * (2 * 3.141592653589793 / segments);
      canvas.drawArc(
        rect.deflate(p.strokeWidth / 2),
        debut,
        (2 * 3.141592653589793 / segments) * (1 - vide),
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_CerclePointille ancien) => ancien.couleur != couleur;
}
