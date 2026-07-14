import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/app_theme.dart';
import '../../media/media_repository.dart';
import '../status_repository.dart';

/// Convertit un hex (#RRGGBB) en Color opaque.
Color colorFromHex(String hex) {
  final h = hex.replaceFirst("#", "");
  return Color(int.parse("FF$h", radix: 16));
}

/// Composition d'un statut texte sur fond coloré (style WhatsApp).
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

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
  bool _publishing = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack("Écris quelque chose");
      return;
    }
    setState(() => _publishing = true);
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    try {
      await repo.createText(text, _palette[_colorIndex]);
      nav.pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Publication impossible");
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// Sélectionne une image ou vidéo depuis la galerie, l'upload, puis publie
  /// le statut média.
  Future<void> _pickAndPublishMedia() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        withData: true,
      );
    } catch (_) {
      _snack("Sélection de média indisponible sur cette plateforme");
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final mime = file.name.toLowerCase().endsWith('.mov') ||
            file.name.toLowerCase().endsWith('.mp4')
        ? 'video/mp4'
        : 'image/jpeg';

    final isVideo = mime.startsWith('video/');

    setState(() => _publishing = true);
    final media = context.read<MediaRepository>();
    final repo = context.read<StatusRepository>();
    final nav = Navigator.of(context);
    try {
      final uploaded = await media.upload(
        Uint8List.fromList(bytes),
        file.name,
        mime,
      );
      await repo.createMedia(
        uploaded.id,
        isVideo ? 'VIDEO' : 'IMAGE',
      );
      nav.pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Publication du média impossible");
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
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
            tooltip: "Publier une photo ou vidéo",
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _publishing ? null : _pickAndPublishMedia,
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
                    border: InputBorder.none,
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
                  FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _publishing ? null : _publish,
                    child: _publishing
                        ? const CircularProgressIndicator(color: AppColors.terracotta)
                        : Icon(Icons.send, color: bg),
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
