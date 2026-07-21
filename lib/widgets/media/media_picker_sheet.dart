import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Résultat de la sélection de médias.
class MediaPickResult {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int? durationMs;

  const MediaPickResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.durationMs,
  });
}

/// Bottom sheet pour sélectionner des médias à envoyer.
/// Supporte : images, vidéos, documents (PDF, Word, Excel, PPT).
class MediaPickerSheet extends StatelessWidget {
  const MediaPickerSheet({super.key});

  /// Affiche le sélecteur et retourne la liste de fichiers sélectionnés.
  static Future<List<MediaPickResult>?> show(BuildContext context) {
    return showModalBottomSheet<List<MediaPickResult>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const MediaPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poignée
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AlanyaColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              "Envoyer un média",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Options
            _option(
              context,
              icon: Icons.photo_library,
              label: "Photos et vidéos",
              subtitle: "Galerie",
              color: AlanyaColors.forest,
              onTap: () => _pickGallery(context),
            ),
            _option(
              context,
              icon: Icons.camera_alt,
              label: "Appareil photo",
              subtitle: "Prendre une photo",
              color: AlanyaColors.terracotta,
              onTap: () => _pickCamera(context),
            ),
            _option(
              context,
              icon: Icons.insert_drive_file,
              label: "Document",
              subtitle: "PDF, Word, Excel, PowerPoint",
              color: const Color(0xFF2196F3),
              onTap: () => _pickDocument(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AlanyaColors.grey500)),
      onTap: onTap,
    );
  }

  Future<void> _pickGallery(BuildContext context) async {
    final picker = ImagePicker();
    final files = await picker.pickMultipleMedia(imageQuality: 85);
    if (files.isEmpty || !context.mounted) return;

    final results = <MediaPickResult>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final name = file.name;
      final mime = _guessMime(name);
      results.add(MediaPickResult(bytes: bytes, fileName: name, mimeType: mime));
    }
    if (context.mounted) Navigator.pop(context, results);
  }

  Future<void> _pickCamera(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null || !context.mounted) return;

    final bytes = await file.readAsBytes();
    final result = MediaPickResult(
      bytes: bytes,
      fileName: file.name,
      mimeType: 'image/jpeg',
    );
    if (context.mounted) Navigator.pop(context, [result]);
  }

  Future<void> _pickDocument(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final results = <MediaPickResult>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      results.add(MediaPickResult(
        bytes: file.bytes!,
        fileName: file.name,
        mimeType: _guessMime(file.name),
      ));
    }
    if (context.mounted) Navigator.pop(context, results);
  }

  String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }
}
