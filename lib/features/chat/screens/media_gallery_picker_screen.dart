import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/compression_image.dart';
import '../../../core/galerie.dart';
import '../../../theme/alanya_theme.dart';
import 'apercu_selection_screen.dart';
import '../../../widgets/media/media_picker_sheet.dart';

/// Sélecteur de médias plein écran, façon WhatsApp.
///
/// Ce que l'ancien chemin ne faisait pas, et qui compte à l'usage :
///   - la sélection est **NUMÉROTÉE** : sur huit photos, l'ordre d'envoi est
///     celui qu'on a choisi, et il se lit à l'écran. Une case cochée ne dit pas
///     dans quel ordre les photos arriveront ;
///   - la galerie est **PAGINÉE** : l'ancienne feuille chargeait 50 éléments et
///     s'arrêtait là, ce qui rendait inatteignable toute photo plus ancienne ;
///   - les **albums** sont sélectionnables, et la durée des vidéos affichée.
///
/// Le plafond de 10 est celui du serveur (`mediaIds.max(10)`) : au-delà, l'envoi
/// est découpé en plusieurs messages. On laisse donc dépasser 10, mais on le DIT.
/// 🔴 LES DEUX BOUTONS DU BAS NE MÈNENT PAS AU MÊME ENDROIT (demande du user,
/// 30/08/2026, captures à l'appui) :
///   - **OK** ferme le sélecteur et ouvre l'écran d'envoi — les médias en
///     grand, la barre de légende en bas, le bouton d'envoi. C'est la sortie ;
///   - **Prévisualiser** ne sort PAS du sélecteur : il montre les photos
///     cochées en grand, sans légende ni envoi, et le retour ramène ici avec la
///     sélection intacte. C'est un coup d'œil, pas une étape.
class MediaGalleryPickerScreen extends StatefulWidget {
  const MediaGalleryPickerScreen({super.key});

  static Future<List<MediaPickResult>?> open(BuildContext context) {
    return Navigator.of(context).push<List<MediaPickResult>>(
      MaterialPageRoute(builder: (_) => const MediaGalleryPickerScreen()),
    );
  }

  @override
  State<MediaGalleryPickerScreen> createState() =>
      _MediaGalleryPickerScreenState();
}

/// Les deux vues de l'en-tête. « Collections » = les albums du téléphone.
enum _Onglet { photos, collections }

class _MediaGalleryPickerScreenState extends State<MediaGalleryPickerScreen> {
  static const int _taillePage = 90;

  _Onglet _onglet = _Onglet.photos;

  /// L'album ouvert DEPUIS L'ONGLET COLLECTIONS, ou `null` si l'on regarde la
  /// liste des albums.
  ///
  /// 🔴 C'EST UN TROISIÈME NIVEAU, pas un troisième onglet (correction du user,
  /// 31/08/2026). Ouvrir un album basculait l'onglet actif sur « Photos » : on
  /// tapait dans Collections et on se retrouvait ailleurs, sans jamais pouvoir
  /// revenir à la liste — et le retour du système sortait carrément de la
  /// galerie. Les deux défauts n'en font qu'un : l'album n'existait pas comme
  /// endroit où l'on se trouve.
  ///
  /// Collections a donc deux états : la LISTE (`null`) et un ALBUM OUVERT. Le
  /// retour va de l'un à l'autre avant de quitter l'écran.
  AssetPathEntity? _albumOuvert;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];

  /// Ordre de sélection : l'index dans cette liste EST le numéro affiché.
  final List<AssetEntity> _choisis = [];

  int _page = 0;
  bool _finPagination = false;
  bool _chargement = true;
  bool _chargementPage = false;
  bool _permissionRefusee = false;
  bool _preparation = false;

  /// L'accès est PARTIEL (Android 14+, « Sélectionner des photos »).
  ///
  /// L'utilisateur ne voit alors qu'une partie de sa galerie. Le taire le
  /// laisserait chercher une photo que l'application n'a pas le droit de lui
  /// montrer — d'où le bandeau et son bouton « Gérer ».
  bool _partiel = false;

  final _defilement = ScrollController();

  @override
  void initState() {
    super.initState();
    _defilement.addListener(_surDefilement);
    _initialise();
  }

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  void _surDefilement() {
    if (!_defilement.hasClients) return;
    // 600 px avant la fin : la page suivante arrive avant que l'utilisateur ne
    // touche le vide.
    if (_defilement.position.pixels >=
        _defilement.position.maxScrollExtent - 600) {
      _chargePageSuivante();
    }
  }

  Future<void> _initialise() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    // 🔴 `hasAccess` et NON `isAuth` : l'accès PARTIEL d'Android 14+ est un oui.
    // Voir `core/galerie.dart` — c'est ce test qui renvoyait tout le monde vers
    // le sélecteur du système.
    if (!accesUtilisable(permission)) {
      setState(() {
        _chargement = false;
        _permissionRefusee = true;
      });
      return;
    }
    _partiel = accesPartiel(permission);
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        // Sans cet ordre, la galerie remonte de la plus VIEILLE photo du
        // téléphone : Android rend `MediaStore` par identifiant croissant.
        filterOption: ordreRecentDAbord,
      );
      if (!mounted) return;
      if (albums.isEmpty) {
        setState(() => _chargement = false);
        return;
      }
      setState(() {
        _albums = albums;
        _album = albums.first;
      });
      await _chargePageSuivante(premiere: true);
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargePageSuivante({bool premiere = false}) async {
    final album = _album;
    if (album == null || _chargementPage || (_finPagination && !premiere)) {
      return;
    }
    setState(() => _chargementPage = true);
    try {
      final lot = await album.getAssetListPaged(page: _page, size: _taillePage);
      if (!mounted) return;
      setState(() {
        _assets.addAll(lot);
        _page++;
        _finPagination = lot.length < _taillePage;
        _chargement = false;
        _chargementPage = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _chargement = false;
          _chargementPage = false;
        });
      }
    }
  }

  Future<void> _changeAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets.clear();
      _page = 0;
      _finPagination = false;
      _chargement = true;
      // La sélection est CONSERVÉE au changement d'album : choisir deux photos
      // dans deux albums différents est un usage courant, et les perdre en
      // changeant de dossier serait une punition.
    });
    await _chargePageSuivante(premiere: true);
  }

  /// Ouvre un album depuis Collections — SANS quitter l'onglet.
  ///
  /// L'onglet actif reste « Collections » : on est entré dans un de ses
  /// dossiers, on n'a pas changé d'endroit. C'est la barre du haut qui dit où
  /// l'on se trouve, en prenant le nom de l'album et une flèche de retour.
  Future<void> _ouvreAlbum(AssetPathEntity album) async {
    setState(() => _albumOuvert = album);
    await _changeAlbum(album);
  }

  /// Referme l'album ouvert et revient à la LISTE des albums.
  ///
  /// ⚠️ Recharge la vue d'ensemble dans la foulée : l'onglet Photos partage la
  /// même grille, et le laisser sur les assets de l'album le ferait mentir au
  /// prochain appui.
  Future<void> _fermeAlbum() async {
    final tous = _albums.firstOrNull;
    setState(() => _albumOuvert = null);
    if (tous != null && _album != tous) await _changeAlbum(tous);
  }

  /// Bascule d'onglet.
  ///
  /// Revenir sur « Collections » montre toujours la LISTE, jamais le dernier
  /// album ouvert : un onglet doit mener au même endroit à chaque appui.
  Future<void> _changeOnglet(_Onglet cible) async {
    if (cible == _onglet && _albumOuvert == null) return;
    setState(() => _onglet = cible);
    await _fermeAlbum();
  }

  void _bascule(AssetEntity asset) {
    setState(() {
      final index = _choisis.indexWhere((a) => a.id == asset.id);
      if (index >= 0) {
        _choisis.removeAt(index);
      } else {
        _choisis.add(asset);
      }
    });
  }

  /// « OK » : lit les octets des assets retenus, dans l'ordre de sélection, et
  /// rend la main à la discussion — qui enchaîne sur l'écran de légende.
  Future<void> _valide() async {
    if (_choisis.isEmpty || _preparation) return;
    setState(() => _preparation = true);
    final resultats = <MediaPickResult>[];
    for (final asset in _choisis) {
      try {
        final octets = await asset.originBytes;
        if (octets == null) continue;
        final fichier = await asset.file;
        /*
         * 🔴 COMPRESSION AVANT ENVOI (rattrapage du web, 31/08/2026).
         *
         * Le mobile envoyait les octets d'origine — 3 à 8 Mo par photo — quand
         * le web les réduit de dix à quinze fois depuis la veille. C'est le
         * mobile qui paie la donnée, des deux côtés de la conversation.
         *
         * La règle vit dans `core/compression_image.dart`, miroir du module du
         * web : mêmes bornes, mêmes refus. Elle rend les octets d'origine à la
         * moindre incertitude.
         */
        final compresse = await compresserAsset(
          asset,
          octets,
          nomFichier: asset.title ?? 'media_${asset.id}',
          mimeType: _mime(asset),
        );
        resultats.add(MediaPickResult(
          bytes: compresse.octets,
          fileName: compresse.nomFichier,
          mimeType: compresse.mimeType,
          durationMs: asset.type == AssetType.video
              ? (asset.duration * 1000).toInt()
              : null,
          // ⚠️ LE CHEMIN RESTE CELUI DE L'ORIGINAL. Il sert à l'aperçu d'une
          // vidéo, et désormais à RELIRE l'original si l'utilisateur refuse la
          // compression — d'où l'intérêt de ne pas garder ses octets en
          // mémoire.
          path: fichier?.path,
          compresse: compresse.compresse,
          tailleOriginale:
              compresse.compresse ? compresse.tailleAvant : null,
        ));
      } catch (_) {
        // Un média illisible (fichier iCloud non téléchargé, corrompu) est
        // écarté sans faire échouer les autres.
      }
    }
    if (!mounted) return;
    if (resultats.isEmpty) {
      setState(() => _preparation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucun média lisible dans la sélection")),
      );
      return;
    }
    Navigator.of(context).pop(resultats);
  }

  /// « Prévisualiser » : les photos cochées, en grand, sans rien d'autre.
  ///
  /// ⚠️ NE FERME PAS LE SÉLECTEUR et ne lit AUCUN octet : l'écran d'aperçu
  /// travaille sur les vignettes des assets. Prévisualiser dix photos ne doit
  /// pas coûter ce que coûte leur envoi.
  Future<void> _previsualise() async {
    if (_choisis.isEmpty || _preparation) return;
    await ApercuSelectionScreen.ouvrir(context, List.of(_choisis));
  }

  String _mime(AssetEntity asset) {
    final nom = asset.title?.toLowerCase() ?? '';
    if (nom.endsWith('.png')) return 'image/png';
    if (nom.endsWith('.gif')) return 'image/gif';
    if (nom.endsWith('.webp')) return 'image/webp';
    if (nom.endsWith('.heic')) return 'image/heic';
    if (nom.endsWith('.mp4')) return 'video/mp4';
    if (nom.endsWith('.mov')) return 'video/quicktime';
    if (asset.type == AssetType.video) return 'video/mp4';
    return 'image/jpeg';
  }

  String _duree(int secondes) {
    final m = secondes ~/ 60;
    final s = secondes % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /*
   * ═══ COULEURS DE L'ÉCRAN ═══
   *
   * 🔴 L'ÉCRAN ÉTAIT SOMBRE EN DUR (façon WhatsApp) ; il porte désormais NOTRE
   * palette (demande du user, 31/08/2026) : le blanc cassé Alanya au lieu du
   * blanc, et le vert de la marque au lieu du bleu de la capture de référence.
   *
   * ⚠️ THEME-AWARE, et pas simplement « repeint en clair ». Le mode Nuit garde
   * un écran sombre : un sélecteur crème s'y allumerait comme une lampe au
   * milieu d'une application noire. La règle du projet est de n'ajouter QUE la
   * branche Nuit sans toucher au clair — ici les deux branches naissent
   * ensemble, l'écran n'ayant jamais été theme-aware.
   *
   * ⚠️ Le VERT ne suit PAS le thème : il appartient à la marque
   * ([AlanyaColors.logoVert], relevé sur le « W » de l'icône), au même titre que
   * le logotype. Le faire dériver d'un thème à l'autre le rendrait décoratif.
   */
  Color get _fond =>
      themed(context, light: AlanyaColors.cream, dark: AlanyaColors.nuit);
  Color get _fondBarre =>
      themed(context, light: AlanyaColors.warmWhite, dark: AlanyaColors.nuit2);
  Color get _surface =>
      themed(context, light: AlanyaColors.sand, dark: AlanyaColors.nuit3);
  Color get _texte =>
      themed(context, light: AlanyaColors.ink, dark: AlanyaColors.craie);
  Color get _texteDoux =>
      themed(context, light: AlanyaColors.grey600, dark: AlanyaColors.craie2);

  /// Le vert de la marque — celui du « W » de l'icône. Il remplace le bleu de
  /// la capture de référence, et sert d'accent unique de cet écran.
  Color get _accent => AlanyaColors.logoVert;

  @override
  Widget build(BuildContext context) {
    final dansUnAlbum = _albumOuvert != null;
    /*
     * 🔴 LE RETOUR SYSTÈME REFERME D'ABORD L'ALBUM (correction du user,
     * 31/08/2026). Il sortait de la galerie entière depuis l'intérieur d'un
     * album : on perdait sa sélection pour avoir voulu revenir à la liste des
     * dossiers. Un niveau de navigation qui s'ouvre doit se refermer par le
     * même geste que partout ailleurs dans Android.
     */
    return PopScope(
      canPop: !dansUnAlbum,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _fermeAlbum();
      },
      child: _echafaudage(dansUnAlbum),
    );
  }

  Widget _echafaudage(bool dansUnAlbum) {
    return Scaffold(
      backgroundColor: _fond,
      appBar: AppBar(
        backgroundColor: _fondBarre,
        foregroundColor: _texte,
        // Dans un album, la flèche revient à la LISTE des albums ; ailleurs,
        // c'est la flèche ordinaire qui referme le sélecteur.
        leading: dansUnAlbum
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: "Retour aux albums",
                onPressed: _fermeAlbum,
              )
            : null,
        /*
         * 🔴 DEUX ONGLETS, PLUS UN NOM D'ALBUM EN GUISE DE TITRE (demande du
         * user, 31/08/2026).
         *
         * L'en-tête affichait le nom de l'album courant — « Recent » — dans un
         * `DropdownButton`. Ça se lisait comme un TITRE : « personne ne peut
         * s'imaginer que c'est cliquable », et la moitié de la galerie
         * (les albums) restait donc introuvable.
         *
         * Deux pastilles côte à côte, l'active pleine : on voit qu'il y a deux
         * endroits, et lequel on regarde. C'est la disposition de la capture
         * fournie.
         *
         * ⚠️ DANS UN ALBUM, LES PASTILLES CÈDENT LA PLACE À SON NOM. Les
         * laisser afficherait « Collections » en actif alors qu'on regarde des
         * photos, et rien ne dirait lesquelles.
         */
        title: dansUnAlbum
            ? Text(_albumOuvert!.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: _texte, fontSize: 17, fontWeight: FontWeight.w600))
            : _onglets(),
        centerTitle: true,
        actions: [
          if (_choisis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text("${_choisis.length}",
                    style: TextStyle(
                        color: _accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      body: Column(children: [
        if (_partiel && !_permissionRefusee) _bandeauPartiel(),
        // Le bandeau « nom de l'album » a disparu : le nom est désormais DANS
        // la barre du haut, avec la flèche qui en sort. Le garder ici le dirait
        // deux fois.
        Expanded(
          child: _permissionRefusee
              ? _refus()
              // La grille sert les DEUX onglets : la vue d'ensemble sous
              // « Photos », et l'album ouvert sous « Collections ». Seule la
              // liste des albums est un affichage à part.
              : (_onglet == _Onglet.collections && _albumOuvert == null)
                  ? _listeAlbums()
                  : _chargement
                      ? Center(
                          child: CircularProgressIndicator(color: _accent))
                      : _assets.isEmpty
                          ? Center(
                              child: Text("Aucun média",
                                  style: TextStyle(color: _texteDoux)))
                          : _grille(),
        ),
      ]),
      bottomNavigationBar: _choisis.isEmpty ? null : _barreBasse(),
    );
  }

  /// Les deux pastilles de l'en-tête : **Photos** et **Collections**.
  ///
  /// Volontairement des boutons pleins/vides plutôt qu'un `TabBar` : il n'y a
  /// pas de balayage entre les deux vues, et un soulignement de `TabBar` se lit
  /// moins bien qu'une pastille pleine sur ce fond sombre.
  Widget _onglets() {
    Widget pastille(String libelle, _Onglet valeur) {
      final actif = _onglet == valeur;
      return GestureDetector(
        onTap: () => _changeOnglet(valeur),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            // Pastille pleine pour l'onglet actif, sourde pour l'autre : c'est
            // la forme de la capture de référence, son bleu remplacé par notre
            // vert.
            color: actif ? _accent : _surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            libelle,
            style: TextStyle(
              color: actif ? Colors.white : _texteDoux,
              fontSize: 14,
              fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      pastille("Photos", _Onglet.photos),
      const SizedBox(width: 8),
      pastille("Collections", _Onglet.collections),
    ]);
  }

  /// L'onglet **Collections** : les albums du téléphone.
  ///
  /// Une vignette de couverture, le nom, et le nombre d'éléments. Choisir un
  /// album l'OUVRE sans quitter l'onglet ; la flèche du haut, comme le retour
  /// du système, ramène à cette liste. La sélection en cours est CONSERVÉE d'un
  /// album à l'autre : choisir dans deux dossiers est un usage courant.
  Widget _listeAlbums() {
    if (_albums.isEmpty) {
      return Center(
        child: Text("Aucun album", style: TextStyle(color: _texteDoux)),
      );
    }
    return ListView.builder(
      itemCount: _albums.length,
      itemBuilder: (_, i) {
        final album = _albums[i];
        return ListTile(
          leading: SizedBox(
            width: 52,
            height: 52,
            child: FutureBuilder<List<AssetEntity>>(
              // Une seule vignette par album : la couverture. En demander plus
              // ferait autant d'allers-retours natifs que d'albums.
              future: album.getAssetListPaged(page: 0, size: 1),
              builder: (_, lot) {
                final premier = lot.data?.firstOrNull;
                if (premier == null) {
                  return Container(color: _surface);
                }
                return FutureBuilder(
                  future: premier
                      .thumbnailDataWithSize(const ThumbnailSize.square(160)),
                  builder: (_, vignette) {
                    final octets = vignette.data;
                    if (octets == null) {
                      return Container(color: _surface);
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(octets,
                          fit: BoxFit.cover, width: 52, height: 52),
                    );
                  },
                );
              },
            ),
          ),
          title: Text(album.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _texte, fontSize: 15)),
          subtitle: FutureBuilder<int>(
            future: album.assetCountAsync,
            builder: (_, compte) => Text(
              compte.data == null ? "" : "${compte.data} élément(s)",
              style: TextStyle(color: _texteDoux, fontSize: 12),
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: _texteDoux, size: 20),
          // 🔴 ON RESTE DANS COLLECTIONS. Basculer sur « Photos » ici était le
          // défaut signalé : l'onglet changeait sous le doigt, et la liste des
          // albums devenait inatteignable.
          onTap: () => _ouvreAlbum(album),
        );
      },
    );
  }

  Widget _refus() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.photo_library_outlined, size: 52, color: _texteDoux),
          const SizedBox(height: 12),
          Text("Accès à la galerie refusé",
              textAlign: TextAlign.center,
              style: TextStyle(color: _texte)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            child: const Text("Ouvrir les paramètres"),
          ),
        ]),
      ),
    );
  }

  Widget _grille() {
    return GridView.builder(
      controller: _defilement,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_finPagination ? 0 : 3),
      itemBuilder: (_, i) {
        if (i >= _assets.length) {
          return Container(
            color: _surface,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _texteDoux),
              ),
            ),
          );
        }
        final asset = _assets[i];
        final rang = _choisis.indexWhere((a) => a.id == asset.id);
        final choisi = rang >= 0;
        return GestureDetector(
          onTap: () => _bascule(asset),
          child: Stack(fit: StackFit.expand, children: [
            FutureBuilder<Uint8List?>(
              future:
                  asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
              builder: (_, snap) {
                if (snap.data == null) {
                  return Container(color: _surface);
                }
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
            if (choisi) Container(color: Colors.black.withValues(alpha: 0.35)),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Le vert de la marque marque la sélection, comme la pastille
                  // d'onglet : un seul accent sur tout l'écran.
                  color: choisi ? _accent : Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                // Le NUMÉRO, pas une coche : c'est l'ordre d'envoi.
                child: choisi
                    ? Text("${rang + 1}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
            ),
            if (asset.type == AssetType.video)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 10),
                    const SizedBox(width: 2),
                    Text(_duree(asset.duration),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 9)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// La barre du bas, calquée sur les captures fournies par le user le
  /// 30/08/2026 : la croix qui vide la sélection, le compte, « Prévisualiser »
  /// et « OK ».
  ///
  /// ⚠️ « OK » MÈNE À L'ÉCRAN D'ENVOI (légende + bouton d'envoi),
  /// « Prévisualiser » montre les photos et ramène ici. Ne pas les intervertir :
  /// c'est la correction demandée par le user après un premier essai qui les
  /// avait inversés.
  Widget _barreBasse() {
    final tropNombreux = _choisis.length > 10;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: _fondBarre,
          // Un filet plutôt qu'une ombre : sur un fond crème, l'ombre se voit
          // à peine et le trait sépare franchement la barre de la grille.
          border: Border(top: BorderSide(color: _surface)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(children: [
          // La croix VIDE la sélection, elle ne ferme pas l'écran : fermer
          // renverrait à la discussion alors que le geste attendu ici est
          // « je recommence ma sélection ».
          IconButton(
            tooltip: "Vider la sélection",
            icon: Icon(Icons.close, color: _texte),
            onPressed: _preparation ? null : () => setState(_choisis.clear),
          ),
          Text(
            "${_choisis.length}",
            style: TextStyle(
                color: _texte, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (tropNombreux)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  // On ne bloque pas : on annonce le découpage, pour que le
                  // résultat dans le fil ne surprenne pas.
                  "10 par message",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _texteDoux, fontSize: 11),
                ),
              ),
            ),
          const Spacer(),
          /*
           * ⚠️ « Prévisualiser » EST FLEXIBLE ET S'ÉLIDE, « OK » NON.
           *
           * Le user a signalé le 31/08/2026 que le bouton OK n'apparaissait
           * pas. Un `Row` dont un enfant demande plus que la largeur
           * disponible ne prévient pas en release : il CLIPPE, et c'est le
           * dernier enfant — OK — qui disparaît. Rendre le libellé long
           * élidable met la contrainte là où elle est supportable ; le bouton
           * de sortie, lui, ne peut jamais être la variable d'ajustement.
           */
          Flexible(
            child: TextButton(
              onPressed: _preparation ? null : _previsualise,
              style: TextButton.styleFrom(foregroundColor: _texte),
              child: const Text("Prévisualiser",
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: _preparation ? null : _valide,
            style: ElevatedButton.styleFrom(
              // Le vert de la marque, à la place du bleu de la capture.
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              // Une taille plancher : même vide de texte, le bouton reste un
              // bouton visible.
              minimumSize: const Size(72, 42),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // Même forme que le bouton de la capture : un rectangle aux coins
              // arrondis, pas une pastille — les onglets, eux, sont des
              // pastilles. Deux formes, deux rôles.
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _preparation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text("OK",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  /// Bandeau d'ACCÈS PARTIEL — Android 14+, « Sélectionner des photos ».
  ///
  /// Sans lui, l'utilisateur cherche dans notre grille une photo que le système
  /// ne nous laisse pas voir, et conclut que l'application est cassée. Le bouton
  /// rouvre la sélection du système.
  Widget _bandeauPartiel() {
    return Material(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(
              "Seules les photos que tu as autorisées sont visibles.",
              style: TextStyle(color: _texte, fontSize: 12),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _accent),
            onPressed: () async {
              await PhotoManager.presentLimited(type: RequestType.common);
              if (!mounted) return;
              // La galerie est relue : l'utilisateur vient d'ajouter des photos,
              // et ne pas les montrer donnerait l'impression que son geste n'a
              // rien fait.
              setState(() {
                _assets.clear();
                _page = 0;
                _finPagination = false;
                _chargement = true;
              });
              await _chargePageSuivante(premiere: true);
            },
            child: const Text("Gérer"),
          ),
        ]),
      ),
    );
  }
}
