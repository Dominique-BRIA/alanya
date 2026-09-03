import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../../core/compression_image.dart' show imageBordMax;
import '../../../widgets/media/media_picker_sheet.dart';
import '../widgets/choix_emoji.dart';

/// Ce que l'éditeur rend à l'écran de publication.
class MediaEdite {
  const MediaEdite({
    required this.octets,
    required this.nomFichier,
    required this.mimeType,
    required this.chemin,
    required this.durationMs,
    this.legende,
  });

  final Uint8List octets;
  final String nomFichier;
  final String mimeType;

  /// Chemin de l'ORIGINAL sur l'appareil. Nul dès que l'image a été aplatie :
  /// les octets ne correspondent alors plus au fichier, et la compression
  /// vidéo — seule à s'en servir — ne concerne pas une image.
  final String? chemin;
  final int? durationMs;

  /// Texte posé sous le média, comme la légende d'un statut WhatsApp.
  final String? legende;
}

/// Un texte ou un emoji posé sur l'image, déplaçable au doigt.
class _Calque {
  _Calque({required this.contenu, required this.couleur, required this.taille});

  final String contenu;
  final Color couleur;
  double taille;

  /// Position du CENTRE, en fraction de la zone d'édition (0 → 1).
  ///
  /// ⚠️ EN FRACTION ET NON EN PIXELS : l'aplatissement se fait à une autre
  /// échelle que l'affichage. Des coordonnées en pixels auraient placé le texte
  /// ailleurs sur l'image finale que là où l'utilisateur l'a posé.
  Offset position = const Offset(0.5, 0.5);
}

/// Un trait dessiné au doigt.
class _Trait {
  _Trait({required this.couleur, required this.epaisseur});

  final Color couleur;
  final double epaisseur;

  /// Points en fraction de la zone d'édition, pour la même raison que ci-dessus.
  final List<Offset> points = [];
}

/// Les outils disponibles en haut de l'éditeur.
enum _Outil { aucun, dessin }

/// ÉDITEUR DE STATUT MÉDIA, façon WhatsApp — image et vidéo.
///
/// Un seul écran pour les deux, avec la même barre d'outils et la même barre de
/// légende : c'est ce qui rend l'enchaînement « je choisis, je décore, je
/// publie » identique quel que soit le contenu.
///
/// 🔴 CE QUE LA VIDÉO NE SAIT PAS FAIRE, ET POURQUOI. Le dessin, le texte et
/// les emojis ne sont proposés que sur une IMAGE. Les incruster dans une vidéo
/// demande de la RÉENCODER avec un filtre — c'est-à-dire MediaCodec + OpenGL
/// écrits à la main, ou FFmpeg, que nous avons écarté (ffmpeg_kit a été retiré
/// par ses auteurs, et il pèse une vingtaine de mégaoctets d'APK).
/// `video_compress`, notre seul outil vidéo, ne sait que transcoder.
/// Afficher les outils pour ensuite perdre les annotations à l'envoi serait
/// pire que de ne pas les proposer : la vidéo garde donc la légende, qui est
/// stockée à part et n'a rien à incruster.
class EditeurMediaStatutScreen extends StatefulWidget {
  const EditeurMediaStatutScreen({super.key, required this.media});

  final MediaPickResult media;

  static Future<MediaEdite?> ouvrir(
    BuildContext context,
    MediaPickResult media,
  ) {
    return Navigator.of(context).push<MediaEdite>(
      MaterialPageRoute(
        builder: (_) => EditeurMediaStatutScreen(media: media),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<EditeurMediaStatutScreen> createState() =>
      _EditeurMediaStatutScreenState();
}

class _EditeurMediaStatutScreenState extends State<EditeurMediaStatutScreen> {
  static const _couleurs = <Color>[
    Colors.white,
    Colors.black,
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];

  final _legendeCtrl = TextEditingController();
  final _zoneEdition = GlobalKey();

  final List<_Calque> _calques = [];
  final List<_Trait> _traits = [];

  /// L'ordre dans lequel les annotations ont été posées, pour défaire la
  /// DERNIÈRE, quelle que soit sa nature. Deux piles séparées auraient annulé
  /// dans un ordre que l'utilisateur ne comprend pas.
  final List<Object> _historique = [];

  _Outil _outil = _Outil.aucun;
  int _couleur = 0;
  double _epaisseur = 6;
  _Calque? _calqueDeplace;

  VideoPlayerController? _video;
  bool _envoiEnCours = false;

  bool get _estVideo => widget.media.mimeType.startsWith('video/');
  bool get _aDesAnnotations => _calques.isNotEmpty || _traits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final chemin = widget.media.path;
    if (_estVideo && chemin != null) {
      final c = VideoPlayerController.file(File(chemin));
      _video = c;
      c
          .initialize()
          .then((_) {
            if (!mounted) return;
            c.setLooping(true);
            c.play();
            setState(() {});
          })
          .catchError((_) {
            if (mounted) setState(() {});
          });
    }
  }

  @override
  void dispose() {
    _legendeCtrl.dispose();
    _video?.dispose();
    super.dispose();
  }

  // ── Annotations ──────────────────────────────────────────────────────────

  void _defaire() {
    if (_historique.isEmpty) return;
    final dernier = _historique.removeLast();
    setState(() {
      if (dernier is _Trait) {
        _traits.remove(dernier);
      } else if (dernier is _Calque) {
        _calques.remove(dernier);
      }
    });
  }

  Future<void> _ajouterEmoji() async {
    final emoji = await choisirEmoji(context);
    if (emoji == null || !mounted) return;
    setState(() {
      final c = _Calque(contenu: emoji, couleur: Colors.white, taille: 56);
      _calques.add(c);
      _historique.add(c);
      _outil = _Outil.aucun;
    });
  }

  Future<void> _ajouterTexte() async {
    final ctrl = TextEditingController();
    final texte = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajouter du texte"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: "Ton texte…"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (texte == null || texte.isEmpty || !mounted) return;
    setState(() {
      final c = _Calque(
        contenu: texte,
        couleur: _couleurs[_couleur],
        taille: 30,
      );
      _calques.add(c);
      _historique.add(c);
      _outil = _Outil.aucun;
    });
  }

  /// Convertit une position locale en fraction de la zone d'édition.
  Offset? _fraction(Offset local) {
    final boite = _zoneEdition.currentContext?.findRenderObject() as RenderBox?;
    if (boite == null || boite.size.isEmpty) return null;
    return Offset(
      (local.dx / boite.size.width).clamp(0.0, 1.0),
      (local.dy / boite.size.height).clamp(0.0, 1.0),
    );
  }

  // ── Aplatissement ────────────────────────────────────────────────────────

  /// Rend l'image AVEC ses annotations, en PNG.
  ///
  /// ⚠️ PNG ET NON JPEG, PARCE QUE FLUTTER NE SAIT EXPORTER QUE ÇA
  /// (`toByteData` n'accepte que `png` et `rawRgba`). Une photo annotée pèse
  /// donc plus lourd qu'avant annotation, et `compresserAsset` la laissera
  /// intacte — il refuse les PNG pour ne pas leur retirer leur transparence.
  /// C'est le prix de l'incrustation ; une photo NON annotée ne passe pas par
  /// ici et garde son JPEG compressé.
  ///
  /// La capture est bornée à [imageBordMax] : sans borne, un grand téléphone
  /// aurait produit une image de plusieurs milliers de pixels de large, très
  /// au-delà de ce qu'un statut affiche.
  Future<Uint8List?> _aplatir() async {
    try {
      final boundary =
          _zoneEdition.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final logique = boundary.size.longestSide;
      if (logique <= 0) return null;
      final ratio = (imageBordMax / logique).clamp(1.0, 4.0);

      final image = await boundary.toImage(pixelRatio: ratio);
      final donnees = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return donnees?.buffer.asUint8List();
    } catch (_) {
      // On préfère envoyer l'original que rien du tout : l'appelant retombe
      // dessus quand cette fonction rend `null`.
      return null;
    }
  }

  String _enPng(String nom) {
    final point = nom.lastIndexOf('.');
    return "${point > 0 ? nom.substring(0, point) : nom}.png";
  }

  Future<void> _publier() async {
    if (_envoiEnCours) return;
    setState(() => _envoiEnCours = true);

    final legende = _legendeCtrl.text.trim();
    var octets = widget.media.bytes;
    var nom = widget.media.fileName;
    var mime = widget.media.mimeType;
    String? chemin = widget.media.path;

    if (!_estVideo && _aDesAnnotations) {
      final aplati = await _aplatir();
      if (aplati != null && aplati.isNotEmpty) {
        octets = aplati;
        nom = _enPng(nom);
        mime = "image/png";
        // Le chemin ne mène plus à ce qu'on envoie.
        chemin = null;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      MediaEdite(
        octets: octets,
        nomFichier: nom,
        mimeType: mime,
        chemin: chemin,
        durationMs: widget.media.durationMs,
        legende: legende.isEmpty ? null : legende,
      ),
    );
  }

  // ── Rendu ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // La légende doit remonter avec le clavier, sans redimensionner l'image.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _barreOutils(),
            Expanded(child: Center(child: _zone())),
            if (_outil == _Outil.dessin) _paletteDessin(),
            _barreLegende(),
          ],
        ),
      ),
    );
  }

  Widget _barreOutils() {
    final actifs = !_estVideo;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        if (_historique.isNotEmpty)
          IconButton(
            tooltip: "Annuler la dernière",
            icon: const Icon(Icons.undo, color: Colors.white),
            onPressed: _defaire,
          ),
        if (actifs) ...[
          IconButton(
            tooltip: "Emoji",
            icon: const Icon(
              Icons.emoji_emotions_outlined,
              color: Colors.white,
            ),
            onPressed: _ajouterEmoji,
          ),
          IconButton(
            tooltip: "Texte",
            icon: const Icon(Icons.title, color: Colors.white),
            onPressed: _ajouterTexte,
          ),
          IconButton(
            tooltip: "Dessin",
            icon: Icon(
              Icons.brush,
              color: _outil == _Outil.dessin
                  ? const Color(0xFF43A047)
                  : Colors.white,
            ),
            onPressed: () => setState(
              () => _outil = _outil == _Outil.dessin
                  ? _Outil.aucun
                  : _Outil.dessin,
            ),
          ),
        ],
      ],
    );
  }

  Widget _zone() {
    return RepaintBoundary(
      key: _zoneEdition,
      child: GestureDetector(
        // Le dessin ne capte le doigt QUE quand son outil est actif : sinon on
        // ne pourrait plus déplacer un texte déjà posé.
        onPanStart: _outil == _Outil.dessin ? _debutTrait : _debutDeplacement,
        onPanUpdate: _outil == _Outil.dessin ? _suiteTrait : _suiteDeplacement,
        onPanEnd: (_) => _calqueDeplace = null,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            _contenu(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PeintreTraits(_traits)),
              ),
            ),
            ..._calques.map(_rendreCalque),
          ],
        ),
      ),
    );
  }

  Widget _contenu() {
    if (_estVideo) {
      final v = _video;
      if (v == null || !v.value.isInitialized) {
        return const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      }
      return AspectRatio(
        aspectRatio: v.value.aspectRatio,
        child: VideoPlayer(v),
      );
    }
    return Image.memory(widget.media.bytes, fit: BoxFit.contain);
  }

  Widget _rendreCalque(_Calque c) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, bc) => Stack(
          children: [
            Positioned(
              left: c.position.dx * bc.maxWidth,
              top: c.position.dy * bc.maxHeight,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: Text(
                  c.contenu,
                  style: TextStyle(
                    color: c.couleur,
                    fontSize: c.taille,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      // Une ombre portée, sinon un texte blanc disparaît sur un
                      // ciel et un texte noir sur une ombre.
                      Shadow(blurRadius: 6, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _debutTrait(DragStartDetails d) {
    final f = _fraction(d.localPosition);
    if (f == null) return;
    setState(() {
      final t = _Trait(couleur: _couleurs[_couleur], epaisseur: _epaisseur);
      t.points.add(f);
      _traits.add(t);
      _historique.add(t);
    });
  }

  void _suiteTrait(DragUpdateDetails d) {
    if (_traits.isEmpty) return;
    final f = _fraction(d.localPosition);
    if (f == null) return;
    setState(() => _traits.last.points.add(f));
  }

  /// Saisit le calque le plus proche du doigt, s'il y en a un assez près.
  void _debutDeplacement(DragStartDetails d) {
    final f = _fraction(d.localPosition);
    if (f == null || _calques.isEmpty) return;
    _Calque? plusProche;
    var distance = double.infinity;
    for (final c in _calques) {
      final dx = c.position.dx - f.dx;
      final dy = c.position.dy - f.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 < distance) {
        distance = d2;
        plusProche = c;
      }
    }
    // ~15 % de la diagonale : au-delà, le doigt ne visait rien.
    if (distance <= 0.15 * 0.15) _calqueDeplace = plusProche;
  }

  void _suiteDeplacement(DragUpdateDetails d) {
    final c = _calqueDeplace;
    if (c == null) return;
    final f = _fraction(d.localPosition);
    if (f == null) return;
    setState(() => c.position = f);
  }

  Widget _paletteDessin() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _couleurs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _couleur = i),
                  child: Container(
                    width: 34,
                    decoration: BoxDecoration(
                      color: _couleurs[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: i == _couleur ? Colors.white : Colors.white24,
                        width: i == _couleur ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Slider(
              value: _epaisseur,
              min: 2,
              max: 20,
              onChanged: (v) => setState(() => _epaisseur = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreLegende() {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 6,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _legendeCtrl,
              maxLength: 700,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                counterText: "",
                hintText: "Ajouter une légende…",
                hintStyle: TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            backgroundColor: Colors.white,
            onPressed: _envoiEnCours ? null : _publier,
            child: _envoiEnCours
                ? const CircularProgressIndicator()
                : const Icon(Icons.send, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _PeintreTraits extends CustomPainter {
  const _PeintreTraits(this.traits);

  final List<_Trait> traits;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in traits) {
      if (t.points.isEmpty) continue;
      final p = Paint()
        ..color = t.couleur
        ..strokeWidth = t.epaisseur
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // Les points sont en fraction : on les remet à l'échelle de la zone. Un
      // trait tracé sur un petit écran se retrouve donc au bon endroit sur
      // l'image aplatie, qui est bien plus grande.
      final chemin = Path();
      final premier = t.points.first;
      chemin.moveTo(premier.dx * size.width, premier.dy * size.height);
      for (final pt in t.points.skip(1)) {
        chemin.lineTo(pt.dx * size.width, pt.dy * size.height);
      }
      // Un point isolé ne trace rien avec `drawPath` : on le rend en pastille.
      if (t.points.length == 1) {
        canvas.drawCircle(
          Offset(premier.dx * size.width, premier.dy * size.height),
          t.epaisseur / 2,
          p..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(chemin, p);
      }
    }
  }

  @override
  bool shouldRepaint(_PeintreTraits ancien) => true;
}
