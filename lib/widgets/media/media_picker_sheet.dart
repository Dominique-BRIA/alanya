import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/galerie.dart';
import '../../theme/alanya_theme.dart';

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

  /// L'image a été RÉDUITE avant l'envoi, et [path] mène encore à l'original.
  ///
  /// Sert à deux choses, toutes deux à l'écran d'envoi : annoncer le gain, et
  /// rendre l'original accessible en un appui. Faux pour une vidéo, un GIF, un
  /// PNG et pour toute image déjà assez petite — voir
  /// `core/compression_image.dart`.
  final bool compresse;

  /// Poids de l'original, quand il a été réduit. `null` sinon.
  ///
  /// ⚠️ ON NE GARDE PAS LES OCTETS D'ORIGINE EN MÉMOIRE. Dix photos de 8 Mo
  /// tenues en double sont 160 Mo dans un téléphone : l'original se relit
  /// depuis [path] au moment où on le demande, et pas avant.
  final int? tailleOriginale;

  const MediaPickResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.durationMs,
    this.path,
    this.compresse = false,
    this.tailleOriginale,
  });

  MediaPickResult copieAvec({
    Uint8List? bytes,
    String? fileName,
    String? mimeType,
    bool? compresse,
  }) =>
      MediaPickResult(
        bytes: bytes ?? this.bytes,
        fileName: fileName ?? this.fileName,
        mimeType: mimeType ?? this.mimeType,
        durationMs: durationMs,
        path: path,
        compresse: compresse ?? this.compresse,
        tailleOriginale: tailleOriginale,
      );

  bool get estImage => mimeType.startsWith('image/');
  bool get estVideo => mimeType.startsWith('video/');
}

/// Demandes rendues par la feuille au lieu d'un résultat : l'écran de
/// discussion doit ouvrir un autre sélecteur.
///
/// ⚠️ **C'est ce qui évite le double `Navigator.pop`** qui refermait la
/// conversation entière (bug du 17/08/2026). Une feuille modale rend son
/// résultat EN SE FERMANT, une seule fois : elle ne peut pas se fermer, puis
/// ouvrir autre chose, puis rendre un résultat — le second `pop` s'appliquerait
/// à la route en dessous, c'est-à-dire à l'écran de discussion.
class OuvrirSelecteurContact {
  const OuvrirSelecteurContact();
}

class OuvrirEcranPosition {
  const OuvrirEcranPosition();
}

class OuvrirGalerie {
  const OuvrirGalerie();
}

class OuvrirCamera {
  const OuvrirCamera();
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
    // 🔴 `hasAccess` et NON `isAuth` : l'accès PARTIEL d'Android 14+ est un oui.
    // Avec `isAuth`, choisir « Sélectionner des photos » faisait déclarer la
    // permission refusée, la bande des récents restait vide et le bouton
    // « Galerie » ouvrait le sélecteur du système. Voir `core/galerie.dart`.
    if (!accesUtilisable(permission)) {
      if (mounted) setState(() { _loadingGallery = false; _permissionDenied = true; });
      return;
    }
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        // Sans cet ordre, « récents » montrait les plus VIEILLES photos.
        filterOption: ordreRecentDAbord,
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
  //
  // Même correction que le contact : la version précédente fermait la feuille
  // puis rappelait `pop` après la prise de vue — ce second `pop` fermait la
  // CONVERSATION. Le `canPop()` ne protégeait de rien : il est vrai, puisqu'il
  // reste toujours une route en dessous.
  void _pickCamera() => Navigator.pop(context, const OuvrirCamera());

  // ══ GALERIE — sélecteur plein écran, ordonné, paginé ══
  //
  // Le sélecteur SYSTÈME (`FilePicker`) reste le repli : il ne numérote pas la
  // sélection, ne pagine pas, et n'indique pas la durée des vidéos. Il sert
  // quand l'accès à la galerie est refusé — un refus de permission ne doit pas
  // empêcher d'envoyer une photo.
  void _pickFullGallery() {
    if (_permissionDenied) {
      // Le sélecteur système s'ouvre SANS quitter cette feuille : il ne passe
      // pas par le navigateur de l'application, donc le résultat peut être rendu
      // par un `pop` unique, comme pour les documents.
      _pickFullGalleryParSysteme(Navigator.of(context));
      return;
    }
    Navigator.pop(context, const OuvrirGalerie());
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

  // ══ DOCUMENTS — TOUS TYPES ══
  //
  // La liste blanche d'extensions (`pdf, doc, docx, xls, xlsx, ppt, pptx, txt,
  // csv`) interdisait d'envoyer une archive, un APK, un fichier audio ou
  // n'importe quoi d'autre — alors que le serveur les accepte : tout type
  // inconnu part en `application/octet-stream`, qui est dans SA liste blanche
  // (`storage.ts`). C'est le client qui refusait, pas le serveur.
  Future<void> _pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final results = <MediaPickResult>[];
    final tropGros = <String>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      // ⚠️ Plafond du serveur (MEDIA_MAX_SIZE_MB, 50 par défaut) : sans ce
      // contrôle, un fichier de 200 Mo était intégralement TÉLÉVERSÉ avant de
      // se faire refuser par un 413. On le dit avant, en nommant le fichier.
      if (file.bytes!.length > _maxOctets) {
        tropGros.add(file.name);
        continue;
      }
      results.add(MediaPickResult(
        bytes: file.bytes!,
        fileName: file.name,
        mimeType: _guessMime(file.name),
        path: file.path,
      ));
    }
    if (!mounted) return;
    if (tropGros.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tropGros.length == 1
            ? "« ${tropGros.first} » dépasse 50 Mo et n'a pas été joint"
            : "${tropGros.length} fichiers dépassent 50 Mo et n'ont pas été joints"),
      ));
    }
    if (results.isNotEmpty) Navigator.pop(context, results);
  }

  /// Taille maximale acceptée par le serveur, en octets.
  static const int _maxOctets = 50 * 1024 * 1024;

  // ══ CONTACT — fiche de contact partagée (type de message CONTACT) ══
  //
  // ⚠️ Ceci n'envoyait AUCUN contact avant le 17/08/2026 : la feuille rendait
  // une liste de numéros, que l'écran de discussion collait dans le champ de
  // saisie pour les envoyer en texte. Le destinataire recevait « 12345678 » et
  // n'avait ni nom, ni photo, ni action.
  //
  // La sélection est rendue à l'appelant (`ContactShareResult`) : c'est lui qui
  // téléverse la photo éventuelle et envoie le message, comme pour les médias.
  /// 🐛 **CORRIGÉ LE 17/08/2026 — CE CHEMIN RENVOYAIT À LA LISTE DES
  /// CONVERSATIONS SANS RIEN ENVOYER** (constaté sur device par le user).
  ///
  /// La version fautive appelait `Navigator.pop()` DEUX FOIS sur le même
  /// navigateur : la première fermait cette feuille, la seconde — censée rendre
  /// le résultat — s'appliquait donc à la route suivante, c'est-à-dire à
  /// **l'écran de discussion lui-même**. D'où le retour à la liste, et le
  /// contact perdu en route.
  ///
  /// Une feuille modale ne peut rendre son résultat qu'en se fermant, UNE fois.
  /// Elle se contente donc d'annoncer ce que l'appelant doit ouvrir ; c'est
  /// l'écran de discussion, toujours vivant, qui présente le sélecteur.
  void _pickContact() => Navigator.pop(context, const OuvrirSelecteurContact());

  // ══ POSITION — vraie position GPS (type de message LOCATION) ══
  //
  // ⚠️ Ceci demandait à l'utilisateur de TAPER ses coordonnées à la main, dans
  // une boîte de dialogue, alors que `geolocator` est dans l'application depuis
  // le chantier de géolocalisation d'entreprise. Personne ne connaît sa
  // latitude. L'écran d'aperçu relève la position, la montre sur une carte, et
  // conserve la saisie manuelle en action secondaire — elle servait à partager
  // un LIEU (une boutique), ce que le GPS du téléphone ne peut pas donner.
  /// Même correction que [_pickContact] : un seul `pop`, et l'écran de
  /// discussion ouvre l'aperçu de position. Le double `pop` refermait la
  /// conversation et perdait la position.
  void _pickLocation() => Navigator.pop(context, const OuvrirEcranPosition());

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
