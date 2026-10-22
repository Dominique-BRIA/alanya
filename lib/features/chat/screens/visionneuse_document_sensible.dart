import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/authed_api.dart';
import '../../../core/ecran_protege.dart';
import '../../../core/infos_appareil.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_media.dart';
import '../../auth/auth_controller.dart';
import '../sortie_document_sensible.dart';

/// La visionneuse d'un DOCUMENT SENSIBLE (18/10/2026, revue le 22/10/2026).
///
/// 🔴 DEMANDE DU PATRON (18/10) : « s'il le télécharge, ça doit en quelque
/// sorte signer avec le numéro Alanya, la marque de l'appareil, la date et
/// l'heure du téléchargement ».
///
/// * le document s'ouvre ICI (PDF, image, vidéo) ;
/// * la signature « Consulté par Alanya 67 64 15 99 · samsung SM-A515F ·
///   18/10/2026 14:32 » court aux QUATRE BORDS (22/10 : elle couvrait toute la
///   page en mosaïque et gênait la lecture) — qui photographie l'écran
///   photographie aussi sa signature ;
/// * l'écran est protégé (`EcranProtege`) : ni capture, ni enregistrement ;
/// * la consultation est tracée côté serveur.
///
/// 22/10 : ENREGISTRER et PARTAGER ne sont plus interdits (demande du user).
/// La copie qui sort est signée à son tour, aux quatre bords et dans ses
/// métadonnées, avec un code de trace noté par le serveur
/// (`SortieDocumentSensible`).
class VisionneuseDocumentSensible extends StatefulWidget {
  const VisionneuseDocumentSensible({
    super.key,
    required this.fichier,
    required this.descripteur,
    this.convId,
    this.expediteurId,
  });

  final File fichier;
  final DescripteurMedia descripteur;
  final String? convId;

  /// L'Alanya ID de l'expéditeur, s'il est connu : écrit dans la copie.
  final String? expediteurId;

  @override
  State<VisionneuseDocumentSensible> createState() =>
      _VisionneuseDocumentSensibleState();
}

class _VisionneuseDocumentSensibleState
    extends State<VisionneuseDocumentSensible> {
  String _signature = '';
  bool _occupe = false;
  VideoPlayerController? _video;

  DescripteurMedia get d => widget.descripteur;
  bool get _pdf =>
      d.mime == 'application/pdf' || (d.nom ?? '').toLowerCase().endsWith('.pdf');
  bool get _image => d.mime.startsWith('image/');
  bool get _estVideo => d.mime.startsWith('video/');

  @override
  void initState() {
    super.initState();
    unawaited(EcranProtege.activer());
    unawaited(_signer());
    if (_estVideo) {
      final c = VideoPlayerController.file(widget.fichier);
      _video = c;
      c.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    unawaited(EcranProtege.desactiver());
    _video?.dispose();
    super.dispose();
  }

  /// Compose la signature, et trace la consultation côté serveur.
  Future<void> _signer() async {
    final api = context.read<AuthedApi>();
    final numero = context.read<AuthController>().user?.publicNumber ?? '';
    final appareil = await InfosAppareil.marqueModele();
    final t = DateTime.now();
    String deux(int n) => n.toString().padLeft(2, '0');
    final quand =
        '${deux(t.day)}/${deux(t.month)}/${t.year} ${deux(t.hour)}:${deux(t.minute)}';
    if (!mounted) return;
    setState(() {
      _signature = tr(context, 'sens_filigrane', {
        'num': formatAlanyaId(numero),
        'appareil': appareil,
        'date': quand,
      });
    });
    try {
      await api.post('/api/documents-sensibles/consultations', {
        'mediaId': d.id,
        if (widget.convId != null) 'convId': widget.convId,
        'appareil': appareil,
      });
    } catch (_) {
      // La trace ne doit jamais empêcher la lecture.
    }
  }

  Future<void> _enregistrer() async {
    final sortie = SortieDocumentSensible.de(context);
    final echec = tr(context, 'download_failed');
    final nonSignee = tr(context, 'sens_copie_non_signee');
    String enregistre(String nom) =>
        tr(context, 'saved_to_alanya', {'nom': nom});
    setState(() => _occupe = true);
    try {
      final r = await sortie.enregistrer(
        clair: widget.fichier,
        d: d,
        convId: widget.convId,
        expediteurId: widget.expediteurId,
      );
      if (!mounted) return;
      if (r.chemin == null) {
        showAppSnackBar(echec);
      } else {
        showAppSnackBar(r.copie.signee ? enregistre(r.copie.nom) : nonSignee);
      }
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _partager() async {
    final sortie = SortieDocumentSensible.de(context);
    final echec = tr(context, 'send_failed');
    final nonSignee = tr(context, 'sens_copie_non_signee');
    setState(() => _occupe = true);
    try {
      final c = await sortie.partager(
        clair: widget.fichier,
        d: d,
        convId: widget.convId,
        expediteurId: widget.expediteurId,
      );
      if (!c.signee) showAppSnackBar(nonSignee);
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Widget _lecteurVideo() {
    final c = _video;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: Stack(alignment: Alignment.center, children: [
        Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (_, v, __) => v.isPlaying
              ? const SizedBox.shrink()
              : const Icon(Icons.play_circle_outline,
                  size: 72, color: Colors.white70),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: VideoProgressIndicator(c, allowScrubbing: true),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget contenu;
    if (_pdf) {
      contenu = PDFView(
        filePath: widget.fichier.path,
        enableSwipe: true,
        autoSpacing: true,
        pageFling: true,
      );
    } else if (_image) {
      contenu = InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.file(widget.fichier)),
      );
    } else if (_estVideo) {
      contenu = _lecteurVideo();
    } else {
      contenu = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr(context, 'sens_format'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1B1B1B),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(children: [
          const Icon(Icons.verified_user_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(d.nom ?? tr(context, 'sens_titre'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
          ),
        ]),
        actions: [
          if (_occupe)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              ),
            )
          else ...[
            IconButton(
              tooltip: tr(context, 'save'),
              icon: const Icon(Icons.download_outlined),
              onPressed: _enregistrer,
            ),
            IconButton(
              tooltip: tr(context, 'share'),
              icon: const Icon(Icons.share_outlined),
              onPressed: _partager,
            ),
          ],
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: contenu),
        // La signature court aux quatre bords, sans jamais capter un toucher.
        if (_signature.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: Bords(_signature)),
            ),
          ),
      ]),
    );
  }
}

/// La signature écrite le long des quatre bords : en haut et en bas de gauche
/// à droite, à gauche de bas en haut, à droite de haut en bas. Trop longue
/// pour un bord, la ligne entière est écrite plus petit.
class Bords extends CustomPainter {
  Bords(this.texte);

  final String texte;

  static const taille = 11.0;
  static const tailleMin = 7.0;
  static const marge = 4.0;
  static const _rouge = Color(0xD9E53935);

  /// La taille de police retenue pour un bord de [longueur].
  static double tailleBord(double largeurNaturelle, double longueur) {
    final place = longueur - 2 * marge;
    if (largeurNaturelle <= place) return taille;
    return max(tailleMin, taille * place / largeurNaturelle);
  }

  TextPainter _peintre(double t) => TextPainter(
        text: TextSpan(
          text: texte,
          style: TextStyle(
            color: _rouge,
            fontSize: t,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 2)],
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final naturel = _peintre(taille).width;
    final h = _peintre(tailleBord(naturel, size.width));
    final v = _peintre(tailleBord(naturel, size.height));

    void ecrire(TextPainter p, Offset centre, double angle) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(angle);
      p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
      canvas.restore();
    }

    ecrire(h, Offset(size.width / 2, marge + h.height / 2), 0);
    ecrire(h, Offset(size.width / 2, size.height - marge - h.height / 2), 0);
    ecrire(v, Offset(marge + v.height / 2, size.height / 2), -pi / 2);
    ecrire(v, Offset(size.width - marge - v.height / 2, size.height / 2), pi / 2);
  }

  @override
  bool shouldRepaint(covariant Bords ancien) => ancien.texte != texte;
}
