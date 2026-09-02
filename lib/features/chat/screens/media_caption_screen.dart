import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/compression_image.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/media_picker_sheet.dart';

/// Ce que l'aperçu rend à l'écran de discussion.
///
/// La LISTE est rendue elle aussi, et pas seulement la légende : l'utilisateur
/// peut retirer un média depuis l'aperçu, et c'est cette liste-là qu'il faut
/// envoyer. L'ancien écran ne rendait qu'un `String?`, si bien qu'aucune
/// suppression n'était possible — il fallait revenir en arrière et tout
/// resélectionner.
class MediaCaptionResult {
  final List<MediaPickResult> fichiers;
  final String? legende;

  /// Les `@` de la légende — `{userId, libelle}`, comme pour un texte.
  ///
  /// Une légende est un message comme un autre : elle peut désigner quelqu'un,
  /// et le serveur la traite pareil.
  final List<Map<String, String>> mentions;

  const MediaCaptionResult({
    required this.fichiers,
    this.legende,
    this.mentions = const [],
  });
}

/// Aperçu des médias avant l'envoi, façon WhatsApp : balayage entre les médias,
/// bandeau de vignettes, suppression, lecture des vidéos, légende commune.
///
/// ⚠️ **Une seule légende pour tout l'envoi**, et ce n'est pas un raccourci : un
/// message porte UN `content` et N médias. Une légende par média demanderait un
/// message par média, donc de casser la grille de réception en autant de bulles.
class MediaCaptionScreen extends StatefulWidget {
  final List<MediaPickResult> files;

  /// Les membres du groupe, `id -> nom`. VIDE hors groupe : le `@` ne propose
  /// alors rien, exactement comme dans le champ de discussion.
  final Map<String, String> membres;

  /// Mon identifiant — on ne se mentionne pas soi-même.
  final String? monId;

  const MediaCaptionScreen({
    super.key,
    required this.files,
    this.membres = const {},
    this.monId,
  });

  static Future<MediaCaptionResult?> open(
    BuildContext context,
    List<MediaPickResult> files, {
    Map<String, String> membres = const {},
    String? monId,
  }) {
    return Navigator.of(context).push<MediaCaptionResult>(
      MaterialPageRoute(
        builder: (_) =>
            MediaCaptionScreen(files: files, membres: membres, monId: monId),
      ),
    );
  }

  @override
  State<MediaCaptionScreen> createState() => _MediaCaptionScreenState();
}

class _MediaCaptionScreenState extends State<MediaCaptionScreen> {
  late final List<MediaPickResult> _fichiers;
  late final PageController _pages;
  final TextEditingController _captionCtrl = TextEditingController();
  int _index = 0;

  /// Un lecteur par vidéo, créé à la demande et libéré à la sortie. Les créer
  /// tous d'avance ouvrirait dix décodeurs pour dix vidéos.
  final Map<int, VideoPlayerController> _lecteurs = {};

  @override
  void initState() {
    super.initState();
    _fichiers = List.of(widget.files);
    _pages = PageController();
    _prepareVideo(0);
  }

  @override
  void dispose() {
    for (final l in _lecteurs.values) {
      l.dispose();
    }
    _pages.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  /// Prépare la vidéo de la page [i], si c'en est une.
  ///
  /// ⚠️ `video_player` lit un CHEMIN, jamais des octets : sans `path`, l'aperçu
  /// retombe sur une icône. C'est le cas des sélecteurs qui ne rendent que des
  /// données (et du web).
  void _prepareVideo(int i) {
    if (i < 0 || i >= _fichiers.length) return;
    final f = _fichiers[i];
    if (!f.estVideo || kIsWeb || f.path == null) return;
    if (_lecteurs.containsKey(i)) return;
    final c = VideoPlayerController.file(File(f.path!));
    _lecteurs[i] = c;
    c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      // Vidéo illisible : on garde l'icône plutôt que d'échouer.
      if (mounted) setState(() => _lecteurs.remove(i)?.dispose());
    });
  }

  void _retire(int i) {
    if (_fichiers.length <= 1) {
      // Retirer le dernier média revient à annuler l'envoi : on le dit ainsi
      // plutôt que de laisser un écran vide.
      Navigator.of(context).pop(null);
      return;
    }
    setState(() {
      _lecteurs.remove(i)?.dispose();
      // Les lecteurs sont indexés par position : après une suppression, les
      // indices glissent. On repart de zéro plutôt que de les réindexer à la
      // main — c'est un décalage silencieux garanti sinon.
      for (final l in _lecteurs.values) {
        l.dispose();
      }
      _lecteurs.clear();
      _fichiers.removeAt(i);
      if (_index >= _fichiers.length) _index = _fichiers.length - 1;
    });
    _pages.jumpToPage(_index);
    _prepareVideo(_index);
  }

  void _envoie() {
    final legende = _captionCtrl.text.trim();
    Navigator.of(context).pop(MediaCaptionResult(
      fichiers: _fichiers,
      legende: legende.isEmpty ? null : legende,
      // Réduites à celles encore présentes dans la légende : effacer
      // « @Dominique » avant d'envoyer ne doit notifier personne. Même règle
      // que dans le champ de discussion.
      mentions: [
        for (final m in _mentionsEnCours)
          if (legende.contains("@${m["libelle"]}")) m,
      ],
    ));
  }

  // ══════════════════════════════════════════════
  // MENTIONS @ DANS LA LÉGENDE — groupes seulement
  // ══════════════════════════════════════════════
  //
  // 🔴 UNE LÉGENDE EST UN MESSAGE COMME UN AUTRE. Le serveur la range dans le
  // même `content`, et rien ne justifiait qu'on puisse mentionner quelqu'un en
  // écrivant, mais pas en envoyant une photo — c'est même souvent là qu'on veut
  // le faire (« @Jean regarde ça »).
  //
  // Miroir de `chat_screen.dart` : mêmes règles de détection, même filtre à
  // l'envoi. Les deux écrans doivent produire les mêmes messages.

  final List<Map<String, String>> _mentionsEnCours = [];
  String? _requeteMention;
  int _debutMention = -1;

  void _majRequeteMention() {
    if (widget.membres.isEmpty) return;
    final sel = _captionCtrl.selection;
    final texte = _captionCtrl.text;
    if (!sel.isValid || !sel.isCollapsed || sel.start > texte.length) {
      if (_requeteMention != null) setState(() => _requeteMention = null);
      return;
    }
    final avant = texte.substring(0, sel.start);
    final at = avant.lastIndexOf('@');
    // Le `@` doit ouvrir un mot, et la requête s'arrête à la première espace.
    if (at < 0 ||
        (at > 0 && !RegExp(r'\s').hasMatch(avant[at - 1])) ||
        avant.substring(at + 1).contains(RegExp(r'\s'))) {
      if (_requeteMention != null) setState(() => _requeteMention = null);
      return;
    }
    setState(() {
      _requeteMention = avant.substring(at + 1);
      _debutMention = at;
    });
  }

  List<MapEntry<String, String>> _membresProposes() {
    final requete = (_requeteMention ?? "").toLowerCase();
    return widget.membres.entries
        .where((e) => e.key != widget.monId && e.value.trim().isNotEmpty)
        .where((e) => requete.isEmpty || e.value.toLowerCase().contains(requete))
        .toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
  }

  void _insereMention(String userId, String nom) {
    final texte = _captionCtrl.text;
    final sel = _captionCtrl.selection;
    final fin = sel.isValid ? sel.start : texte.length;
    if (_debutMention < 0 || _debutMention > fin) return;
    // L'espace finale évite que le curseur reste DANS la mention, ce qui
    // rouvrirait la liste sur le nom qu'on vient de choisir.
    final remplacement = "@$nom ";
    _captionCtrl.value = TextEditingValue(
      text: texte.replaceRange(_debutMention, fin, remplacement),
      selection:
          TextSelection.collapsed(offset: _debutMention + remplacement.length),
    );
    setState(() {
      _requeteMention = null;
      _debutMention = -1;
      _mentionsEnCours.removeWhere((m) => m["userId"] == userId);
      _mentionsEnCours.add({"userId": userId, "libelle": nom});
    });
  }

  Widget _panneauMentions() {
    if (widget.membres.isEmpty || _requeteMention == null) {
      return const SizedBox.shrink();
    }
    final membres = _membresProposes();
    if (membres.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      color: const Color(0xFF1F2C34),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: membres.length,
        itemBuilder: (_, i) {
          final e = membres[i];
          return ListTile(
            dense: true,
            title: Text(e.value, style: const TextStyle(color: Colors.white)),
            onTap: () => _insereMention(e.key, e.value),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fichiers.isEmpty) return const SizedBox.shrink();
    final courant = _fichiers[_index];

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text(
          _fichiers.length > 1
              ? "${_index + 1} / ${_fichiers.length}"
              : courant.fileName,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: "Retirer ce média",
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: () => _retire(_index),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _fichiers.length,
                onPageChanged: (i) {
                  // La vidéo qu'on quitte se met en pause : sinon le son
                  // continue sur la page suivante.
                  _lecteurs[_index]?.pause();
                  setState(() => _index = i);
                  _prepareVideo(i);
                },
                itemBuilder: (_, i) => Center(child: _apercu(i)),
              ),
            ),
            if (_fichiers.length > 1) _bandeau(),
            ?_ligneCompression(),
            _panneauMentions(),
            _composeur(),
          ],
        ),
      ),
    );
  }

  Widget _apercu(int i) {
    final f = _fichiers[i];
    if (f.estImage) {
      return InteractiveViewer(
        maxScale: 4,
        child: Image.memory(f.bytes, fit: BoxFit.contain),
      );
    }
    final lecteur = _lecteurs[i];
    if (f.estVideo && lecteur != null && lecteur.value.isInitialized) {
      return GestureDetector(
        onTap: () => setState(
            () => lecteur.value.isPlaying ? lecteur.pause() : lecteur.play()),
        child: Stack(alignment: Alignment.center, children: [
          AspectRatio(
            aspectRatio: lecteur.value.aspectRatio,
            child: VideoPlayer(lecteur),
          ),
          if (!lecteur.value.isPlaying)
            const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(lecteur, allowScrubbing: true),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(f.estVideo ? Icons.movie_outlined : Icons.insert_drive_file,
            size: 64, color: Colors.white70),
        const SizedBox(height: 12),
        Text(
          f.fileName,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _bandeau() {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _fichiers.length,
        itemBuilder: (_, i) {
          final f = _fichiers[i];
          final actif = i == _index;
          return GestureDetector(
            onTap: () {
              _pages.jumpToPage(i);
              setState(() => _index = i);
              _prepareVideo(i);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8, top: 5, bottom: 5),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                border: Border.all(
                  color: actif ? AlanyaColors.gold : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: f.estImage
                    ? Image.memory(f.bytes, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFF1F2C34),
                        child: Icon(
                            f.estVideo
                                ? Icons.movie_outlined
                                : Icons.insert_drive_file,
                            color: Colors.white70,
                            size: 22),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// « Compressée · 4,2 Mo → 320 Ko · **Envoyer l'original** ».
  ///
  /// 🔴 DIRE CE QU'ON A FAIT, ET LAISSER LE REFUSER (rattrapage du web,
  /// 31/08/2026). Réduire une photo sans le dire est une décision prise à la
  /// place de quelqu'un : celui qui envoie une ordonnance, un reçu ou un plan
  /// veut ses pixels, et il n'a aucun moyen de deviner qu'on les lui a retirés.
  ///
  /// ⚠️ L'ORIGINAL SE RELIT DEPUIS LE DISQUE, il n'est pas gardé en mémoire :
  /// dix photos de 8 Mo tenues en double feraient tomber l'application. Le
  /// chemin vient du sélecteur ; sans lui (envoi web, sélecteur système qui ne
  /// rend que des octets) la ligne ne s'affiche pas, faute de pouvoir tenir sa
  /// promesse.
  Widget? _ligneCompression() {
    final courant = _fichiers[_index];
    if (!courant.compresse || courant.path == null) return null;
    final avant = courant.tailleOriginale;
    if (avant == null) return null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        const Icon(Icons.compress, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            "${poidsLisible(avant)} → ${poidsLisible(courant.bytes.length)}",
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _restaureOriginal,
          child: const Text(
            "Envoyer l'original",
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline),
          ),
        ),
      ]),
    );
  }

  /// Remplace les octets réduits par ceux du fichier d'origine.
  ///
  /// Sans retour en arrière : reprendre la version réduite demanderait de la
  /// garder en mémoire à côté de l'original, pour une hésitation. Celui qui
  /// change d'avis ressort et resélectionne — c'est deux appuis, et ça ne coûte
  /// la mémoire de personne.
  Future<void> _restaureOriginal() async {
    final courant = _fichiers[_index];
    final chemin = courant.path;
    if (chemin == null) return;
    try {
      final octets = await File(chemin).readAsBytes();
      if (!mounted) return;
      setState(() {
        _fichiers[_index] = courant.copieAvec(
          bytes: octets,
          // Le nom et le type redeviennent ceux de l'original : le serveur
          // choisit l'extension de stockage d'après le NOM, et des octets
          // d'origine sous un nom `.jpg` seraient servis avec le mauvais
          // en-tête. Même règle qu'à la compression, dans l'autre sens.
          fileName: chemin.split(Platform.pathSeparator).last,
          compresse: false,
        );
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("L'original sera envoyé")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Original introuvable — envoi réduit")),
      );
    }
  }

  Widget _composeur() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF111B21),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3942),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _captionCtrl,
                onChanged: (_) => _majRequeteMention(),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: _fichiers.length > 1
                      ? "Légende (tous les médias)"
                      : "Ajouter une légende…",
                  hintStyle:
                      const TextStyle(color: Colors.white54, fontSize: 15),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _envoie,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AlanyaColors.gold,
                shape: BoxShape.circle,
              ),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.send, color: Colors.white, size: 22),
                if (_fichiers.length > 1)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("${_fichiers.length}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
