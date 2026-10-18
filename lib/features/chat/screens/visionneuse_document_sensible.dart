import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/authed_api.dart';
import '../../../core/ecran_protege.dart';
import '../../../core/infos_appareil.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/e2ee/e2ee_media.dart';
import '../../auth/auth_controller.dart';

/// La visionneuse d'un DOCUMENT SENSIBLE (18/10/2026).
///
/// 🔴 DEMANDE DU PATRON : « s'il le télécharge, ça doit en quelque sorte signer
/// avec le numéro Alanya, la marque de l'appareil, la date et l'heure du
/// téléchargement ; le fichier ne doit pas pouvoir être repartagé ».
///
/// * le document s'ouvre ICI, jamais dans une autre application (qui
///   permettrait de l'enregistrer ou de l'envoyer ailleurs) ;
/// * un filigrane couvre chaque page : « Alanya 67 64 15 99 · samsung SM-A515F
///   · 18/10/2026 14:32 » — qui fait une photo de l'écran photographie aussi sa
///   signature ;
/// * l'écran est protégé (`EcranProtege`) : ni capture, ni enregistrement, ni
///   aperçu dans les applications récentes ;
/// * la consultation est tracée côté serveur (qui, quel appareil, quand).
///
/// ⚠️ CE QU'AUCUNE APPLICATION NE PEUT EMPÊCHER : photographier l'écran avec
/// un autre téléphone. Le filigrane est la réponse : la fuite porte le nom de
/// celui qui l'a faite.
class VisionneuseDocumentSensible extends StatefulWidget {
  const VisionneuseDocumentSensible({
    super.key,
    required this.fichier,
    required this.descripteur,
    this.convId,
  });

  final File fichier;
  final DescripteurMedia descripteur;
  final String? convId;

  @override
  State<VisionneuseDocumentSensible> createState() =>
      _VisionneuseDocumentSensibleState();
}

class _VisionneuseDocumentSensibleState
    extends State<VisionneuseDocumentSensible> {
  String _filigrane = '';

  DescripteurMedia get d => widget.descripteur;
  bool get _pdf =>
      d.mime == 'application/pdf' || (d.nom ?? '').toLowerCase().endsWith('.pdf');
  bool get _image => d.mime.startsWith('image/');

  @override
  void initState() {
    super.initState();
    unawaited(EcranProtege.activer());
    unawaited(_signer());
  }

  @override
  void dispose() {
    unawaited(EcranProtege.desactiver());
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
      _filigrane = tr(context, 'sens_filigrane', {
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
      ),
      body: Stack(children: [
        Positioned.fill(child: contenu),
        // Le filigrane couvre tout, sans jamais capter un toucher.
        if (_filigrane.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Filigrane(_filigrane)),
            ),
          ),
      ]),
    );
  }
}

/// La signature, répétée en diagonale sur toute la surface.
class _Filigrane extends CustomPainter {
  _Filigrane(this.texte);

  final String texte;

  @override
  void paint(Canvas canvas, Size size) {
    final peintre = TextPainter(
      text: TextSpan(
        text: texte,
        style: const TextStyle(
          color: Color(0x40E53935),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-pi / 6);
    final diag = sqrt(size.width * size.width + size.height * size.height);
    final pasX = peintre.width + 48;
    const pasY = 90.0;
    var ligne = 0;
    for (var y = -diag / 2; y < diag / 2; y += pasY) {
      final decalage = (ligne++ % 2) * pasX / 2;
      for (var x = -diag / 2 - decalage; x < diag / 2; x += pasX) {
        peintre.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Filigrane ancien) => ancien.texte != texte;
}
