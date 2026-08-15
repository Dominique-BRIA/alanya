import 'package:flutter/material.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/media_picker_sheet.dart';

class MediaCaptionScreen extends StatefulWidget {
  final List<MediaPickResult> files;

  const MediaCaptionScreen({super.key, required this.files});

  static Future<String?> open(BuildContext context, List<MediaPickResult> files) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MediaCaptionScreen(files: files),
      ),
    );
  }

  @override
  State<MediaCaptionScreen> createState() => _MediaCaptionScreenState();
}

class _MediaCaptionScreenState extends State<MediaCaptionScreen> {
  int _currentIndex = 0;
  final TextEditingController _captionCtrl = TextEditingController();

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = widget.files[_currentIndex];
    final isImage = current.mimeType.startsWith('image/');

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
          widget.files.length > 1
              ? "${_currentIndex + 1} / ${widget.files.length}"
              : current.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: isImage
                    ? Image.memory(
                        current.bytes,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2C34),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 64, color: Colors.white70),
                            const SizedBox(height: 12),
                            Text(
                              current.fileName,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (widget.files.length > 1)
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: widget.files.length,
                  itemBuilder: (_, i) {
                    final f = widget.files[i];
                    final isSel = i == _currentIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _currentIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSel ? AlanyaColors.gold : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: f.mimeType.startsWith('image/')
                              ? Image.memory(f.bytes, fit: BoxFit.cover)
                              : const Icon(Icons.insert_drive_file, color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Container(
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
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          hintText: "Ajouter une légende...",
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop(_captionCtrl.text.trim());
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AlanyaColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
