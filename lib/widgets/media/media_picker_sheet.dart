import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import '../../features/chat/screens/location_share_screen.dart';
import '../../features/chat/screens/media_gallery_picker_screen.dart';
import '../../theme/alanya_theme.dart';
import '../contact_share_sheet.dart';

/// Résultat de la sélection de médias.
class MediaPickResult {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int? durationMs;

  /// Chemin du fichier sur l'appareil, quand la source en fournit un.
  ///
  /// Indispensable à l'APERÇU D'UNE VIDÉO : `video_player` et
  /// `video_thumbnail` lisent un chemin, jamais des octets. Sans lui, une vidéo
  /// sélectionnée n'était représentée que par une icône de fichier — on ne
  /// voyait pas ce qu'on allait envoyer. Nul sur le web, et nul si le
  /// sélecteur système ne rend que des octets : l'aperçu retombe alors sur
  /// l'icône, ce qui reste correct.
  final String? path;

  const MediaPickResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.durationMs,
    this.path,
  });

  bool get estImage => mimeType.startsWith('image/');
  bool get estVideo => mimeType.startsWith('video/');
}

/// Bottom sheet style WhatsApp pour envoyer des médias :
/// - 4 options : Galerie, Caméra, Document, Contact
/// - Galerie récente en bas (thumbnails horizontaux, multi-sélection)
class MediaPickerSheet extends StatefulWidget {
  const MediaPickerSheet({super.key});

  static Future<dynamic> show(BuildContext context) {
    return showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MediaPickerSheet(),
    );
  }

  @override
  State<MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<MediaPickerSheet> {
  List<AssetEntity> _recentMedia = [];
  bool _loadingGallery = true;
  bool _permissionDenied = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadRecentMedia();
  }

  Future<void> _loadRecentMedia() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) setState(() { _loadingGallery = false; _permissionDenied = true; });
      return;
    }
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() => _loadingGallery = false);
        return;
      }
      final recent = await albums[0].getAssetListPaged(page: 0, size: 50);
      if (mounted) setState(() { _recentMedia = recent; _loadingGallery = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingGallery = false);
    }
  }

  void _toggleSelect(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  // ══ CONFIRMER SÉLECTION GALERIE RÉCENTE ══
  Future<void> _confirmSelection() async {
    if (_selectedIds.isEmpty) return;
    final results = <MediaPickResult>[];
    for (final asset in _recentMedia) {
      if (!_selectedIds.contains(asset.id)) continue;
      final bytes = await asset.originBytes;
      if (bytes == null) continue;
      final name = asset.title ?? 'media_${asset.id}';
      final mime = _mimeFromAsset(asset);
      results.add(MediaPickResult(
        bytes: bytes,
        fileName: name,
        mimeType: mime,
        durationMs: asset.type == AssetType.video ? (asset.duration * 1000).toInt() : null,
        // Chemin réel de l'asset : c'est ce qui permet de LIRE une vidéo dans
        // l'aperçu au lieu d'afficher une icône.
        path: (await asset.file)?.path,
      ));
    }
    if (mounted && results.isNotEmpty) Navigator.pop(context, results);
  }

  // ══ CAMÉRA ══
  Future<void> _pickCamera() async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final result = MediaPickResult(
        bytes: bytes,
        fileName: photo.name,
        mimeType: 'image/jpeg',
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop([result]);
      }
    } catch (_) {}
  }

  // ══ GALERIE — sélecteur plein écran, ordonné, paginé ══
  //
  // Le sélecteur SYSTÈME (`FilePicker`) reste le repli : il ne numérote pas la
  // sélection, ne pagine pas, et n'indique pas la durée des vidéos. Il sert
  // quand l'accès à la galerie est refusé — un refus de permission ne doit pas
  // empêcher d'envoyer une photo.
  Future<void> _pickFullGallery() async {
    final navigator = Navigator.of(context);
    if (_permissionDenied) {
      await _pickFullGalleryParSysteme(navigator);
      return;
    }
    navigator.pop();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final choisis = await MediaGalleryPickerScreen.open(context);
    if (choisis != null && choisis.isNotEmpty) navigator.pop(choisis);
  }

  Future<void> _pickFullGalleryParSysteme(NavigatorState navigator) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final results = <MediaPickResult>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        results.add(MediaPickResult(
          bytes: file.bytes!,
          fileName: file.name,
          mimeType: _guessMime(file.name),
          path: file.path,
        ));
      }
      if (mounted && results.isNotEmpty) navigator.pop(results);
    } catch (_) {}
  }

  // ══ DOCUMENTS ══
  Future<void> _pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final results = <MediaPickResult>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      results.add(MediaPickResult(
        bytes: file.bytes!,
        fileName: file.name,
        mimeType: _guessMime(file.name),
      ));
    }
    if (mounted && results.isNotEmpty) Navigator.pop(context, results);
  }

  // ══ CONTACT — fiche de contact partagée (type de message CONTACT) ══
  //
  // ⚠️ Ceci n'envoyait AUCUN contact avant le 17/08/2026 : la feuille rendait
  // une liste de numéros, que l'écran de discussion collait dans le champ de
  // saisie pour les envoyer en texte. Le destinataire recevait « 12345678 » et
  // n'avait ni nom, ni photo, ni action.
  //
  // La sélection est rendue à l'appelant (`ContactShareResult`) : c'est lui qui
  // téléverse la photo éventuelle et envoie le message, comme pour les médias.
  Future<void> _pickContact() async {
    final navigator = Navigator.of(context);
    // La feuille de sélection remplace celle-ci : on referme d'abord, sinon
    // deux feuilles modales se superposent et la seconde hérite de la hauteur
    // contrainte de la première.
    navigator.pop();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final resultat = await ContactShareSheet.show(context);
    if (resultat != null && resultat.contacts.isNotEmpty) {
      // La feuille appelante est déjà fermée : on rend le résultat par le
      // navigateur qu'elle a laissé, celui de l'écran de discussion.
      navigator.pop(resultat);
    }
  }

  // ══ POSITION — vraie position GPS (type de message LOCATION) ══
  //
  // ⚠️ Ceci demandait à l'utilisateur de TAPER ses coordonnées à la main, dans
  // une boîte de dialogue, alors que `geolocator` est dans l'application depuis
  // le chantier de géolocalisation d'entreprise. Personne ne connaît sa
  // latitude. L'écran d'aperçu relève la position, la montre sur une carte, et
  // conserve la saisie manuelle en action secondaire — elle servait à partager
  // un LIEU (une boutique), ce que le GPS du téléphone ne peut pas donner.
  Future<void> _pickLocation() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final position = await LocationShareScreen.open(context);
    if (position != null) navigator.pop(position);
  }

  String _mimeFromAsset(AssetEntity asset) {
    final name = asset.title?.toLowerCase() ?? '';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.mp4')) return 'video/mp4';
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (asset.type == AssetType.video) return 'video/mp4';
    return 'image/jpeg';
  }

  String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default: return 'application/octet-stream';
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AlanyaColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 4 options (style WhatsApp)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _optionButton(
                  icon: Icons.photo_library,
                  label: "Galerie",
                  color: AlanyaColors.forest,
                  onTap: _pickFullGallery,
                ),
                _optionButton(
                  icon: Icons.camera_alt,
                  label: "Caméra",
                  color: const Color(0xFFE53935),
                  onTap: _pickCamera,
                ),
                _optionButton(
                  icon: Icons.insert_drive_file,
                  label: "Document",
                  color: const Color(0xFF7B1FA2),
                  onTap: _pickDocuments,
                ),
                _optionButton(
                  icon: Icons.person,
                  label: "Contact",
                  color: const Color(0xFF2196F3),
                  onTap: _pickContact,
                ),
                _optionButton(
                  icon: Icons.location_on,
                  label: "Position",
                  color: const Color(0xFF009688),
                  onTap: _pickLocation,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Label "Récents" + bouton Envoyer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text(
                  "Récents",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_selectedIds.isNotEmpty)
                  GestureDetector(
                    onTap: _confirmSelection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AlanyaColors.terracotta,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "Envoyer (${_selectedIds.length})",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Galerie récente
          Expanded(
            child: _loadingGallery
                ? const Center(child: CircularProgressIndicator(color: AlanyaColors.terracotta))
                : _permissionDenied
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_off, size: 48, color: AlanyaColors.grey400),
                            const SizedBox(height: 12),
                            Text("Accès aux fichiers refusé",
                                style: TextStyle(color: AlanyaColors.grey500, fontSize: 14)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => PhotoManager.openSetting(),
                              child: const Text("Ouvrir les paramètres"),
                            ),
                          ],
                        ),
                      )
                    : _recentMedia.isEmpty
                        ? Center(child: Text("Aucun média récent",
                            style: TextStyle(color: AlanyaColors.grey400)))
                        : _buildGalleryGrid(),
          ),
        ],
      ),
    );
  }

  Widget _optionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildGalleryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      scrollDirection: Axis.horizontal,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: _recentMedia.length,
      itemBuilder: (ctx, i) {
        final asset = _recentMedia[i];
        final selected = _selectedIds.contains(asset.id);
        final isVideo = asset.type == AssetType.video;

        return GestureDetector(
          onTap: () => _toggleSelect(asset),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                builder: (ctx, snap) {
                  if (!snap.hasData || snap.data == null) {
                    return Container(color: AlanyaColors.grey200);
                  }
                  return Image.memory(snap.data!, fit: BoxFit.cover);
                },
              ),
              if (selected) Container(color: AlanyaColors.terracotta.withValues(alpha: 0.3)),
              Positioned(
                top: 4, right: 4,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: selected ? AlanyaColors.terracotta : Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
              ),
              if (isVideo)
                Positioned(
                  bottom: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.videocam, color: Colors.white, size: 10),
                      const SizedBox(width: 2),
                      Text(_formatDuration(asset.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
