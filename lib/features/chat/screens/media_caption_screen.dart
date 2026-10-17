import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/compression_envoi.dart';
import '../../../core/plafond_media.dart';
import '../../../core/compression_image.dart';
import '../../../core/compression_video.dart' show videoBordCourtHaute;
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/avancement_compression.dart';
import '../../../widgets/media/media_picker_sheet.dart';
import '../../../l10n/app_localizations.dart';
import 'visionneur_vue_unique.dart' show PastilleVueUnique;

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

  /// Envoi À VUE UNIQUE (une seule photo ou vidéo, sans légende).
  final bool vueUnique;

  const MediaCaptionResult({
    required this.fichiers,
    this.legende,
    this.mentions = const [],
    this.vueUnique = false,
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

  /// Le « 1 » de WhatsApp : envoyer à vue unique.
  bool _vueUnique = false;

  /// L'index du média en cours de recompression, et son avancement (0 à 1).
  ///
  /// 🔴 ON BLOQUE L'ENVOI PENDANT CE TEMPS. Partir avec les octets de l'ancien
  /// niveau alors que l'utilisateur vient d'en demander un autre serait lui
  /// désobéir en silence — et transcoder une vidéo prend des secondes.
  int? _recompresse;
  double _avancementNiveau = 0;

  /// Offert seulement pour UNE photo ou UNE vidéo : le serveur refuse un lot,
  /// et un document n'a pas de sens à vue unique.
  bool get _vueUniquePossible =>
      _fichiers.length == 1 &&
      (_fichiers.first.mimeType.startsWith('image/') ||
          _fichiers.first.mimeType.startsWith('video/'));

  /// Un lecteur par vidéo, créé à la demande et libéré à la sortie. Les créer
  /// tous d'avance ouvrirait dix décodeurs pour dix vidéos.
  final Map<int, VideoPlayerController> _lecteurs = {};

  /// L'index en cours de PREMIÈRE compression, et son avancement.
  ///
  /// 🔴 LA COMPRESSION A QUITTÉ LE SÉLECTEUR POUR CET ÉCRAN (décision du user,
  /// 13/10/2026 : « quand on sélectionne une vidéo, ça doit aller dans le
  /// lecteur intégré, qui sert de page intermédiaire, AVANT de charger le
  /// pourcentage de compression »).
  ///
  /// 🔴 ET C'EST BIEN MIEUX AINSI. Transcoder dans le sélecteur retenait la
  /// grille, doigt levé, sans que rien ne soit encore visible de ce qu'on
  /// envoie. Ici, la vidéo se regarde et la légende s'écrit pendant que le
  /// transcodage tourne — exactement ce que fait le web depuis toujours.
  int? _compresse;
  double _avancementCompression = 0;

  /// Vrai tant qu'un fichier attend sa première compression : l'envoi patiente.
  bool _enPreparation = false;

  @override
  void initState() {
    super.initState();
    _fichiers = List.of(widget.files);
    _pages = PageController();
    _prepareVideo(0);
    unawaited(_compresserCeQuiReste());
  }

  /// Compresse les fichiers que le sélecteur a laissés intacts — les vidéos.
  ///
  /// ⚠️ UN PAR UN, et c'est voulu : les encodeurs matériels sont en nombre
  /// limité, et deux transcodages simultanés finissent tous les deux plus tard
  /// qu'en file.
  ///
  /// ⚠️ NE LÈVE JAMAIS. Une vidéo qui refuse de se transcoder part telle
  /// quelle : c'est la règle de tout le module de compression.
  Future<void> _compresserCeQuiReste() async {
    final aFaire = <int>[
      for (var i = 0; i < _fichiers.length; i++)
        if (!_fichiers[i].compresse && _fichiers[i].estVideo) i,
    ];
    if (aFaire.isEmpty) return;
    if (mounted) setState(() => _enPreparation = true);

    for (final i in aFaire) {
      if (!mounted) return;
      final m = _fichiers[i];
      setState(() {
        _compresse = i;
        _avancementCompression = 0;
      });
      try {
        final pret = await compresserPourEnvoi(
          asset: m.asset,
          octets: m.bytes,
          nomFichier: m.fileName,
          mimeType: m.mimeType,
          chemin: m.path,
          onProgression: (v) {
            if (mounted) setState(() => _avancementCompression = v);
          },
        );
        if (!mounted) return;
        setState(() {
          _fichiers[i] = m.copieAvec(
            bytes: pret.octets,
            fileName: pret.nomFichier,
            mimeType: pret.mimeType,
            compresse: pret.compresse,
            tailleOriginale: pret.compresse ? pret.tailleAvant : null,
            niveauSuperieurPossible: pret.niveauSuperieurPossible,
            definitionAutreNiveau: pret.definitionAutreNiveau,
          );
        });
      } catch (_) {
        // La vidéo partira telle quelle.
      }
    }

    if (!mounted) return;
    setState(() {
      _compresse = null;
      _enPreparation = false;
    });

    /*
     * ⚠️ LE PLAFOND SE MESURE MAINTENANT, et pas avant : une vidéo de 80 Mo en
     * fait 6 une fois transcodée. La refuser sur sa taille d'origine aurait
     * écarté un envoi parfaitement acceptable.
     */
    final tropGros = <String>[];
    for (var i = _fichiers.length - 1; i >= 0; i--) {
      if (depassePlafondMedia(_fichiers[i].bytes.length)) {
        tropGros.add(_fichiers[i].fileName);
        setState(() => _fichiers.removeAt(i));
      }
    }
    if (tropGros.isEmpty || !mounted) return;
    final avis = messageMediasEcartes(tropGros, context: context);
    if (avis != null) showAppSnackBar(avis);
    if (_fichiers.isEmpty && mounted) Navigator.of(context).pop();
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
    /*
     * ⚠️ PAS D'ENVOI PENDANT UNE RECOMPRESSION. L'utilisateur vient de demander
     * un autre niveau ; partir avec les octets de l'ancien serait lui désobéir
     * en silence, et un transcodage vidéo prend des secondes.
     */
    if (_recompresse != null) return;
    /*
     * ⚠️ PAS D'ENVOI TANT QU'UNE VIDÉO SE TRANSCODE. Partir avec les octets
     * d'origine enverrait les 80 Mo qu'on est précisément en train de réduire —
     * et le serveur les refuserait. L'utilisateur voit le pourcentage ; le
     * bouton attend qu'il finisse.
     */
    if (_enPreparation) return;
    final vueUnique = _vueUnique && _vueUniquePossible;
    // Une vue unique part SANS légende : elle resterait lisible bien après
    // l'effacement du média.
    final legende = vueUnique ? '' : _captionCtrl.text.trim();
    Navigator.of(context).pop(MediaCaptionResult(
      fichiers: _fichiers,
      vueUnique: vueUnique,
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
            tooltip: tr(context, 'remove_media'),
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

  /// « 4,2 Mo → 320 Ko · **Meilleure qualité** », ou « 30 Mo → 3,9 Mo · **1080p** ».
  ///
  /// 🔴 DIRE CE QU'ON A FAIT, ET LAISSER LE CHANGER (rattrapage du web,
  /// 31/08/2026). Réduire une photo sans le dire est une décision prise à la
  /// place de quelqu'un : celui qui envoie une ordonnance, un reçu ou un plan
  /// veut ses pixels, et il n'a aucun moyen de deviner qu'on les lui a retirés.
  ///
  /// ⚠️ RIEN N'EST INVENTÉ POUR MEUBLER : quand il n'y a rien à annoncer, la
  /// ligne ne paraît pas — exactement le web (décision du user, 12/10/2026 :
  /// « lorsque le mobile ne peut pas compresser, il n'affiche juste pas ce
  /// truc-là »).
  ///
  /// ⚠️ ELLE RESTE AFFICHÉE AU NIVEAU HAUT MÊME SANS GAIN, sinon le bouton du
  /// retour disparaîtrait avec elle et l'utilisateur serait enfermé dans le
  /// niveau qu'il vient de choisir.
  ///
  /// 🐛 ELLE NE S'AFFICHAIT JAMAIS SUR LE MOBILE (signalé par le user le
  /// 13/10/2026 : « même quand ça doit compresser, ça n'affiche pas ça »).
  /// Elle exigeait TROIS choses pour paraître : une compression, un chemin de
  /// fichier, et une taille d'origine. Les deux dernières servent au BOUTON et
  /// à la FLÈCHE, pas au fait qu'il y ait quelque chose à dire — et il manque
  /// souvent un chemin (photo venue du nuage, fichier partagé par une autre
  /// application). Toute la ligne disparaissait alors, gain compris.
  ///
  /// ⚠️ CHAQUE MORCEAU A DÉSORMAIS SA PROPRE CONDITION :
  ///   · la ligne paraît dès qu'il y a eu compression ;
  ///   · la flèche « avant → après » demande la taille d'origine ;
  ///   · le bouton demande le chemin — sans lui on ne pourrait pas repartir de
  ///     l'original, et le proposer serait une promesse qu'on ne tient pas.
  Widget? _ligneCompression() {
    final courant = _fichiers[_index];

    // Pendant une compression — la première comme un changement de niveau.
    if (_compresse == _index || _recompresse == _index) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          const Icon(Icons.compress, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          AvancementCompression(
            avancement:
                _compresse == _index ? _avancementCompression : _avancementNiveau,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ]),
      );
    }

    final haute = courant.niveau == NiveauQualite.haute;
    if (!courant.compresse && !haute) return null;
    final avant = courant.tailleOriginale;

    /*
     * 🐛 L'ÉTIQUETTE ANNONÇAIT « Envoyer en 1080p » QUOI QU'IL ARRIVE, et
     * « Envoyer en 720p » pour en revenir. C'était faux dès que la source
     * faisait moins : une vidéo filmée en 720p ne rend pas du 1080p, on
     * n'agrandit jamais — et depuis l'escalier elle part en 360p, si bien que le
     * retour se fait vers 720p, non vers 1080p. Le bouton dit maintenant la
     * définition qu'il va réellement produire (voir
     * `definitionAutreNiveauVideo`).
     */
    final bascule = courant.estVideo
        ? (haute ? 'media_revenir_definition' : 'media_envoyer_definition')
        : (haute ? 'media_qualite_normale' : 'media_meilleure_qualite');
    final parametresBascule = courant.estVideo
        ? {'def': '${courant.definitionAutreNiveau ?? videoBordCourtHaute}'}
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        const Icon(Icons.compress, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            courant.compresse && avant != null
                ? "${poidsLisible(avant)} → ${poidsLisible(courant.bytes.length)}"
                : poidsLisible(courant.bytes.length),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        // Le bouton ne paraît que s'il change quelque chose : pour une photo de
        // 1200 px ou une vidéo filmée en 720p, le niveau haut rendrait le même
        // fichier. Au niveau haut, il reste pour pouvoir revenir.
        // ⚠️ LE CHEMIN EST REQUIS POUR LE BOUTON SEUL : la bascule repart de
        // l'original sur le disque. Sans lui, on dit le gain sans proposer
        // mieux, plutôt que de ne rien dire du tout.
        if (_rebasculable(courant) && (courant.niveauSuperieurPossible || haute)) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _basculerNiveau,
            child: Text(
              tr(context, bascule, parametresBascule),
              style: TextStyle(
                  color: haute ? AlanyaColors.gold : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline),
            ),
          ),
        ],
      ]),
    );
  }

  /// Recompresse le média courant à l'AUTRE niveau — 1080p / 2560 px, ou retour.
  ///
  /// 🔴 IL A REMPLACÉ « ENVOYER L'ORIGINAL » (décision du user, 12/10/2026).
  /// L'original partait tel quel — 5 Mo pour une photo, 30 à 200 Mo pour une
  /// vidéo — et sur une connexion lente, cet envoi n'aboutissait pas. Le niveau
  /// haut borne ce qui part en restant bien plus près de l'original.
  ///
  /// 🔴 ON REPART DE L'ORIGINAL SUR LE DISQUE, jamais des octets déjà réduits :
  /// recompresser une réduction empilerait deux pertes. C'est aussi pourquoi
  /// l'original n'est pas gardé en mémoire — dix photos de 8 Mo tenues en
  /// double feraient tomber l'application.
  ///
  /// ⚠️ UNE RECOMPRESSION À LA FOIS, et l'envoi attend : partir avec les octets
  /// de l'ancien niveau serait désobéir en silence.
  /// Peut-on vraiment rebasculer ce média ?
  ///
  /// ⚠️ UNE VIDÉO EXIGE UN CHEMIN : le transcodeur natif lit un fichier, jamais
  /// des octets. Une PHOTO se contente de la référence de galerie — c'est par
  /// elle que passe l'encodeur JPEG du téléphone. Sans l'une ni l'autre, le
  /// bouton ne paraît pas : promettre ce qu'on ne peut pas tenir est pire que
  /// de ne rien proposer.
  static bool _rebasculable(MediaPickResult m) =>
      m.path != null || (!m.estVideo && m.asset != null);

  Future<void> _basculerNiveau() async {
    if (_recompresse != null) return;
    final index = _index;
    final courant = _fichiers[index];
    final chemin = courant.path;
    if (!_rebasculable(courant)) return;

    final vise = courant.niveau == NiveauQualite.haute
        ? NiveauQualite.normal
        : NiveauQualite.haute;
    setState(() {
      _recompresse = index;
      _avancementNiveau = 0;
    });
    try {
      /*
       * ⚠️ L'ORIGINAL VIENT DU DISQUE, OU DE LA GALERIE. Une photo du nuage n'a
       * pas toujours de chemin local : `originBytes` la fait descendre, et
       * c'est la seule façon d'honorer le bouton pour elle.
       */
      final original = chemin != null
          ? await File(chemin).readAsBytes()
          : (await courant.asset!.originBytes)!;
      final nom = chemin != null
          ? chemin.split(Platform.pathSeparator).last
          : courant.fileName;
      final pret = await compresserPourEnvoi(
        asset: courant.asset,
        octets: original,
        // Le nom et le type de l'ORIGINAL : la compression leur rendra ceux du
        // JPEG ou du MP4 produit. Repartir du nom déjà transformé étiquetterait
        // des octets d'origine en `.jpg`, et le serveur les servirait plus tard
        // avec le mauvais en-tête.
        nomFichier: nom,
        mimeType: mimeDepuisNom(nom, repli: courant.mimeType),
        chemin: chemin,
        niveau: vise,
        onProgression: (v) {
          if (mounted) setState(() => _avancementNiveau = v);
        },
      );
      if (!mounted) return;
      setState(() {
        _fichiers[index] = courant.copieAvec(
          bytes: pret.octets,
          fileName: pret.nomFichier,
          mimeType: pret.mimeType,
          compresse: pret.compresse,
          tailleOriginale: original.length,
          niveauSuperieurPossible: pret.niveauSuperieurPossible,
          definitionAutreNiveau: pret.definitionAutreNiveau,
          niveau: vise,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'original_missing'))),
      );
    } finally {
      if (mounted) setState(() => _recompresse = null);
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
              child: Row(children: [
               Expanded(
              child: TextField(
                controller: _captionCtrl,
                enabled: !(_vueUnique && _vueUniquePossible),
                onChanged: (_) => _majRequeteMention(),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: _vueUnique && _vueUniquePossible
                      ? tr(context, 'vu_titre')
                      : _fichiers.length > 1
                          ? tr(context, 'caption_all_media')
                          : tr(context, 'status_add_caption'),
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
                // LE « 1 » DE WHATSAPP, dans le champ, contre le bord droit.
                if (_vueUniquePossible)
                  IconButton(
                    tooltip: tr(context, 'vu_activer'),
                    onPressed: () {
                      setState(() => _vueUnique = !_vueUnique);
                      if (_vueUnique) {
                        _captionCtrl.clear();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                              content: Text(tr(context, 'vu_active_info'))));
                      }
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _vueUnique ? AlanyaColors.gold : Colors.transparent,
                      ),
                      child: PastilleVueUnique(
                          taille: 24,
                          couleur: _vueUnique ? Colors.white : Colors.white70),
                    ),
                  ),
              ]),
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
