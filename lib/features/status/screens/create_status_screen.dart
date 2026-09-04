import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/compression_image.dart' show imageBordMax, imageQualite;
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/media_picker_sheet.dart' show MediaPickResult;
import '../../chat/screens/media_gallery_picker_screen.dart';
import '../../media/media_repository.dart';
import '../publication_statuts.dart';
import '../status_repository.dart';
import '../widgets/choix_emoji.dart';
import 'editeur_media_statut_screen.dart';
import 'status_viewer_screen.dart' show dureeVideoStatutMax;

/// Convertit un hex (#RRGGBB) en Color opaque.
Color colorFromHex(String hex) {
  final h = hex.replaceFirst("#", "");
  return Color(int.parse("FF$h", radix: 16));
}

/// Par où l'on entre dans la composition d'un statut.
///
/// Le bouton « + » de l'onglet Status propose les quatre, et l'écran ouvre
/// directement la bonne source : sans ça, choisir « Appareil photo » aurait
/// affiché l'éditeur de texte avant d'ouvrir la caméra, ce qui donne
/// l'impression de s'être trompé de bouton.
enum SourceStatut { texte, galerie, cameraPhoto, cameraVideo }

/// Composition d'un statut texte sur fond coloré (style WhatsApp).
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key, this.source = SourceStatut.texte});

  final SourceStatut source;

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  static const _palette = <String>[
    "#C75B39", // terracotta
    "#2E6F40", // forest
    "#5A3825", // chocolate
    "#B07D56", // clay
    "#2C3E50",
    "#8E44AD",
    "#16A085",
    "#C0392B",
  ];

  final _textCtrl = TextEditingController();
  int _colorIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.source == SourceStatut.texte) return;
    // Après la première trame : ouvrir un sélecteur depuis `initState` pousse
    // une route sur un Navigator encore en train de bâtir celle-ci.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.source) {
        case SourceStatut.galerie:
          _pickAndPublishMedia();
        case SourceStatut.cameraPhoto:
          _capturer(video: false);
        case SourceStatut.cameraVideo:
          _capturer(video: true);
        case SourceStatut.texte:
          break;
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  /// Prise de vue, photo ou vidéo.
  ///
  /// ⚠️ LES BORNES SONT POSÉES À LA CAPTURE, pas après.
  /// - Photo : `image_picker` sait réduire pendant la prise, aux MÊMES bornes
  ///   que la galerie (`core/compression_image.dart`) — le fichier n'existe
  ///   donc jamais en pleine définition du capteur, ce qui est plus sobre que
  ///   de recompresser ensuite. Même chemin que la caméra de la discussion.
  /// - Vidéo : `maxDuration` coupe à l'enregistrement. Sans lui, on filmerait
  ///   dix minutes pour se faire refuser à l'envoi, la visionneuse ne lisant
  ///   qu'une minute.
  Future<void> _capturer({required bool video}) async {
    XFile? fichier;
    try {
      final picker = ImagePicker();
      fichier = video
          ? await picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: dureeVideoStatutMax,
            )
          : await picker.pickImage(
              source: ImageSource.camera,
              maxWidth: imageBordMax.toDouble(),
              maxHeight: imageBordMax.toDouble(),
              imageQuality: imageQualite,
            );
    } catch (_) {
      _snack("Appareil photo indisponible");
      _refermeSiEntreeMedia();
      return;
    }
    // Renoncer à la prise de vue doit ramener à la liste, pas à l'éditeur de
    // texte — même raison que pour le sélecteur.
    if (fichier == null || !mounted) {
      _refermeSiEntreeMedia();
      return;
    }

    final octets = await fichier.readAsBytes();
    if (!mounted) return;
    await _editerPuisPublier([
      MediaPickResult(
        bytes: octets,
        fileName: fichier.name,
        mimeType: video ? 'video/mp4' : 'image/jpeg',
        path: fichier.path,
      ),
    ]);
  }

  Future<void> _publish() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack("Écris quelque chose");
      return;
    }
    // Même traitement que les médias : l'écran rend la main tout de suite,
    // l'envoi se poursuit derrière. Plus rien ne tourne sur le bouton.
    PublicationStatuts.instance.publierTexte(
      text,
      _palette[_colorIndex],
      statuts: context.read<StatusRepository>(),
      surEchec: () => showAppSnackBar("Statut non publié. Réessaie."),
    );
    Navigator.of(context).pop(true);
  }

  /// Sélectionne des médias, les téléverse, puis publie un statut par média.
  ///
  /// 🔴 PASSE PAR LE SÉLECTEUR DE LA DISCUSSION, ET C'EST TOUT L'INTÉRÊT.
  ///
  /// L'ancien chemin ouvrait `FilePicker` et envoyait les octets D'ORIGINE :
  /// 3 à 8 Mo pour une photo de téléphone, affichée dans un écran qui n'en
  /// montre qu'un dixième. `MediaGalleryPickerScreen` applique déjà la règle
  /// de `core/compression_image.dart` — miroir du web, bord long 1600 px,
  /// qualité 82, et retour aux octets d'origine à la moindre incertitude.
  /// Écrire une seconde compression ici aurait fait deux règles à tenir
  /// accordées.
  ///
  /// Il corrige au passage un défaut du chemin précédent : le type était
  /// deviné sur l'extension, et seuls `.mov` et `.mp4` étaient reconnus — un
  /// PNG, un WebP ou un GIF partaient étiquetés `image/jpeg`.
  Future<void> _pickAndPublishMedia() async {
    List<MediaPickResult>? choisis;
    try {
      choisis = await MediaGalleryPickerScreen.open(context);
    } catch (_) {
      _snack("Sélection de média indisponible sur cette plateforme");
      _refermeSiEntreeMedia();
      return;
    }
    if (choisis == null || choisis.isEmpty || !mounted) {
      _refermeSiEntreeMedia();
      return;
    }
    await _editerPuisPublier(choisis);
  }

  /// Referme l'écran quand on y est entré PAR UN MÉDIA et qu'on renonce.
  ///
  /// 🔴 DÉFAUT SIGNALÉ SUR DEVICE (04/09/2026) : « je mets une photo en statut,
  /// à la fin l'écran de mettre un texte s'ouvre ». Choisir « Galerie » ou
  /// « Appareil photo » pousse cet écran — donc l'éditeur de TEXTE — puis
  /// ouvre le sélecteur par-dessus. Renoncer au sélecteur ou à l'éditeur
  /// laissait l'utilisateur devant un écran de texte qu'il n'avait pas demandé.
  void _refermeSiEntreeMedia() {
    if (widget.source == SourceStatut.texte) return;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Fait passer CHAQUE média par l'éditeur, puis publie ce qui en ressort.
  ///
  /// Un média dont on quitte l'éditeur par le retour est simplement écarté :
  /// c'est le geste d'annulation, il ne doit pas interrompre les autres.
  Future<void> _editerPuisPublier(List<MediaPickResult> choisis) async {
    // ⚠️ Une vidéo plus longue que la visionneuse ne sert à rien : elle serait
    // coupée à `dureeVideoStatutMax` à la lecture, APRÈS avoir été téléversée
    // en entier. On le dit avant l'envoi plutôt que de faire payer la donnée.
    if (choisis.any(
        (m) => (m.durationMs ?? 0) > dureeVideoStatutMax.inMilliseconds)) {
      _snack("Une vidéo de statut ne peut pas dépasser "
          "${dureeVideoStatutMax.inSeconds} secondes");
      _refermeSiEntreeMedia();
      return;
    }

    // L'édition se fait AVANT toute compression et tout envoi : rien ne part
    // sur le réseau tant que l'utilisateur n'a pas validé chaque média.
    final prets = <MediaEdite>[];
    for (final m in choisis) {
      if (!mounted) return;
      final edite = await EditeurMediaStatutScreen.ouvrir(context, m);
      if (edite != null) prets.add(edite);
    }
    if (prets.isEmpty || !mounted) {
      _refermeSiEntreeMedia();
      return;
    }

    /*
     * 🔴 L'ÉCRAN REND LA MAIN TOUT DE SUITE — l'envoi continue sans lui.
     *
     * Trois défauts signalés sur device tenaient à la même cause : la
     * publication se faisait ICI. Il fallait regarder l'écran tourner jusqu'au
     * bout ; l'indicateur s'affichait sur le bouton d'envoi du statut TEXTE,
     * resté derrière ; et quitter l'application pendant un transcodage perdait
     * l'envoi.
     *
     * `PublicationStatuts` passe par `CentreTransferts`, qui démarre le service
     * Android de premier plan : c'est LUI qui empêche Android de tuer le
     * processus quand on sort de l'application. La progression se lit dans la
     * notification, comme pour un envoi de fichier.
     */
    PublicationStatuts.instance.publierMedias(
      prets,
      media: context.read<MediaRepository>(),
      statuts: context.read<StatusRepository>(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Insère un emoji À L'ENDROIT DU CURSEUR, pas à la fin.
  ///
  /// ⚠️ Un emoji ne demande AUCUN changement serveur : c'est du texte, il part
  /// dans la même colonne que le reste. C'est aussi pourquoi il fonctionne, là
  /// où le style du texte demanderait une colonne que `statut` n'a pas.
  Future<void> _insererEmoji() async {
    final emoji = await choisirEmoji(context);
    if (emoji == null || !mounted) return;
    final texte = _textCtrl.text;
    final selection = _textCtrl.selection;
    // Une sélection peut être invalide tant que le champ n'a jamais eu le
    // focus : on écrit alors à la fin.
    final debut = selection.start < 0 ? texte.length : selection.start;
    final fin = selection.end < 0 ? texte.length : selection.end;
    final nouveau = texte.replaceRange(debut, fin, emoji);
    _textCtrl.value = TextEditingValue(
      text: nouveau,
      selection: TextSelection.collapsed(offset: debut + emoji.length),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final bg = colorFromHex(_palette[_colorIndex]);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text("Nouveau statut"),
        actions: [
          IconButton(
            tooltip: "Emoji",
            icon: const Icon(Icons.emoji_emotions_outlined),
            onPressed: _insererEmoji,
          ),
          IconButton(
            tooltip: "Publier une photo ou vidéo",
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _pickAndPublishMedia,
          ),
          IconButton(
            tooltip: "Changer la couleur",
            icon: const Icon(Icons.palette),
            onPressed: () =>
                setState(() => _colorIndex = (_colorIndex + 1) % _palette.length),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: _textCtrl,
                  maxLength: 700,
                  maxLines: null,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  cursorColor: Colors.white,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    /*
                     * 🔴 LES QUATRE ÉTATS, PAS SEULEMENT `border`.
                     *
                     * Le thème global pose un `OutlineInputBorder` sur
                     * `enabledBorder` ET `focusedBorder` : `border` seul ne les
                     * remplace pas, et le cadre terre cuite réapparaissait
                     * autour du texte dès que le champ prenait le focus
                     * (signalé sur device le 04/09/2026). Un statut se compose
                     * en plein écran — aucun cadre n'a de sens ici.
                     */
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    // Contour-matériel (résout le fond blanc hérité du thème global).
                    filled: true,
                    fillColor: Colors.transparent,
                    counterStyle: const TextStyle(color: Colors.white70),
                    hintText: "Tape ton statut…",
                    hintStyle: const TextStyle(color: Colors.white60, fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _palette.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => setState(() => _colorIndex = i),
                          child: Container(
                            width: 40,
                            decoration: BoxDecoration(
                              color: colorFromHex(_palette[i]),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: i == _colorIndex ? Colors.white : Colors.white24,
                                width: i == _colorIndex ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Plus aucun indicateur ici : la publication ne bloque plus
                  // l ecran, elle se poursuit en arriere-plan.
                  FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _publish,
                    child: Icon(Icons.send, color: bg),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
