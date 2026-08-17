import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../theme/alanya_theme.dart';
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

class _MediaGalleryPickerScreenState extends State<MediaGalleryPickerScreen> {
  static const int _taillePage = 90;

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
    if (!permission.isAuth) {
      setState(() {
        _chargement = false;
        _permissionRefusee = true;
      });
      return;
    }
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
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

  /// Lit les octets des assets retenus, dans l'ordre de sélection.
  Future<void> _valide() async {
    if (_choisis.isEmpty || _preparation) return;
    setState(() => _preparation = true);
    final resultats = <MediaPickResult>[];
    for (final asset in _choisis) {
      try {
        final octets = await asset.originBytes;
        if (octets == null) continue;
        final fichier = await asset.file;
        resultats.add(MediaPickResult(
          bytes: octets,
          fileName: asset.title ?? 'media_${asset.id}',
          mimeType: _mime(asset),
          durationMs: asset.type == AssetType.video
              ? (asset.duration * 1000).toInt()
              : null,
          path: fichier?.path,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111B21),
        foregroundColor: Colors.white,
        title: _albums.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<AssetPathEntity>(
                  value: _album,
                  dropdownColor: const Color(0xFF1F2C34),
                  iconEnabledColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: _albums
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (a) {
                    if (a != null) _changeAlbum(a);
                  },
                ),
              )
            : const Text("Galerie"),
        actions: [
          if (_choisis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text("${_choisis.length}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: _chargement
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white54))
          : _permissionRefusee
              ? _refus()
              : _assets.isEmpty
                  ? const Center(
                      child: Text("Aucun média",
                          style: TextStyle(color: Colors.white54)))
                  : _grille(),
      bottomNavigationBar: _choisis.isEmpty ? null : _barreBasse(),
    );
  }

  Widget _refus() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.photo_library_outlined,
              size: 52, color: Colors.white38),
          const SizedBox(height: 12),
          const Text("Accès à la galerie refusé",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
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
            color: const Color(0xFF1F2C34),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white24),
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
                  return Container(color: const Color(0xFF1F2C34));
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
                  color: choisi
                      ? AlanyaColors.terracotta
                      : Colors.black.withValues(alpha: 0.35),
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

  Widget _barreBasse() {
    final tropNombreux = _choisis.length > 10;
    return SafeArea(
      child: Container(
        color: const Color(0xFF111B21),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${_choisis.length} sélectionné${_choisis.length > 1 ? "s" : ""}",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (tropNombreux)
                  const Text(
                    // On ne bloque pas : on annonce le découpage, pour que le
                    // résultat dans le fil ne surprenne pas.
                    "Envoi en plusieurs messages (10 par message)",
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _preparation ? null : _valide,
            icon: _preparation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.arrow_forward, size: 18),
            label: const Text("Suivant"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AlanyaColors.terracotta,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ]),
      ),
    );
  }
}
