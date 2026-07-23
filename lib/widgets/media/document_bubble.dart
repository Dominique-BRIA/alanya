import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:microsoft_viewer/microsoft_viewer.dart';
import '../../core/media_helper.dart';
import '../../theme/alanya_theme.dart';

/// Bulle document style WhatsApp :
/// - PDF : aperçu 1ère page via pdfx
/// - Word/Excel/PPT : aperçu via microsoft_viewer
/// - Autres : icône colorée + nom + taille
class DocumentBubble extends StatefulWidget {
  const DocumentBubble({
    super.key,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.pdfUrl,
    this.token,
    this.onTap,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final String fileName;
  final int? fileSize;
  final String? mimeType;
  final String? pdfUrl;
  final String? token;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  State<DocumentBubble> createState() => _DocumentBubbleState();
}

class _DocumentBubbleState extends State<DocumentBubble> {
  Uint8List? _previewBytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _generatePreview();
  }

  @override
  void didUpdateWidget(DocumentBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfUrl != widget.pdfUrl) {
      _previewBytes = null;
      _failed = false;
      _generatePreview();
    }
  }

  bool get _isPdf {
    final mime = widget.mimeType ?? '';
    final ext = MediaHelper.extension(widget.fileName).toLowerCase();
    return mime == 'application/pdf' || ext == '.pdf';
  }

  bool get _isMicrosoft {
    final ext = MediaHelper.extension(widget.fileName).toLowerCase();
    return ['.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx'].contains(ext);
  }

  Future<void> _generatePreview() async {
    if (widget.pdfUrl == null || _loading || _failed) return;
    // Génère un aperçu pour PDF ET documents Microsoft
    if (!_isPdf && !_isMicrosoft) return;

    setState(() => _loading = true);
    try {
      final url = widget.token != null
          ? '${widget.pdfUrl}?token=${widget.token}'
          : widget.pdfUrl!;

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (mounted) setState(() { _failed = true; _loading = false; });
        return;
      }

      if (_isPdf) {
        // PDF : rend la première page
        final doc = await PdfDocument.openData(response.bodyBytes);
        final page = await doc.getPage(1);
        final render = await page.render(
          width: 200,
          height: 280,
          format: PdfPageImageFormat.jpeg,
        );
        await page.close();
        await doc.close();
        if (mounted && render != null) {
          setState(() { _previewBytes = render.bytes; _loading = false; });
        } else {
          if (mounted) setState(() { _failed = true; _loading = false; });
        }
      } else if (_isMicrosoft) {
        // Microsoft : on a les bytes pour MicrosoftViewer
        if (mounted) setState(() { _previewBytes = response.bodyBytes; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = MediaHelper.detectType(widget.mimeType, widget.fileName);
    final icon = MediaHelper.iconForType(type);
    final color = MediaHelper.colorForType(type);
    final ext = MediaHelper.extension(widget.fileName).toUpperCase().replaceAll('.', '');
    final size = MediaHelper.formatSize(widget.fileSize);
    final onText = widget.isMe ? Colors.white : AlanyaColors.ink;
    final onSub = widget.isMe ? Colors.white70 : Colors.black45;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PDF avec aperçu 1ère page
          if (_isPdf && _previewBytes != null)
            _buildPdfPreview(onText, onSub, ext, size)
          // Microsoft avec aperçu via MicrosoftViewer
          else if (_isMicrosoft && _previewBytes != null)
            _buildMicrosoftPreview(onText, onSub, ext, size)
          // Loading
          else if (_loading)
            _buildLoading(onText, onSub, ext, size)
          // Fallback icône
          else
            _buildDocRow(icon, color, ext, size, onText, onSub),

          // Timestamp + coches
          if (widget.timestamp != null) ...[
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Spacer(),
              Text(widget.timestamp!, style: TextStyle(fontSize: 11, color: onSub)),
              if (widget.statusWidget != null) ...[
                const SizedBox(width: 3),
                widget.statusWidget!,
              ],
            ]),
          ],
        ],
      ),
    );
  }

  /// Aperçu PDF — miniature de la 1ère page.
  Widget _buildPdfPreview(Color onText, Color onSub, String ext, String size) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _previewBytes!,
            width: 240,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 8),
        _buildFileInfo(const Color(0xFFE53935), Icons.picture_as_pdf, 'PDF', onText, onSub, size),
      ],
    );
  }

  /// Aperçu Word/Excel/PPT — via MicrosoftViewer.
  Widget _buildMicrosoftPreview(Color onText, Color onSub, String ext, String size) {
    final color = MediaHelper.colorForType(
      MediaHelper.detectType(widget.mimeType, widget.fileName),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Aperçu du document via MicrosoftViewer
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 240,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AlanyaColors.grey200, width: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MicrosoftViewer(_previewBytes!, true),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildFileInfo(color, MediaHelper.iconForType(
          MediaHelper.detectType(widget.mimeType, widget.fileName),
        ), ext, onText, onSub, size),
      ],
    );
  }

  /// Loading pendant la génération.
  Widget _buildLoading(Color onText, Color onSub, String ext, String size) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isMe ? Colors.white.withValues(alpha: 0.08) : AlanyaColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        const SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(strokeWidth: 2, color: AlanyaColors.terracotta),
        ),
        const SizedBox(height: 8),
        Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onText)),
        if (size.isNotEmpty) Text(size, style: TextStyle(fontSize: 10, color: onSub)),
      ]),
    );
  }

  /// Ligne classique pour les fichiers sans aperçu.
  Widget _buildDocRow(IconData icon, Color color, String ext, String size, Color onText, Color onSub) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: widget.isMe ? Colors.white.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: widget.isMe ? Colors.white : color, size: 22),
          if (ext.isNotEmpty)
            Text(ext, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: widget.isMe ? Colors.white70 : color, letterSpacing: 0.5)),
        ]),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.fileName, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onText, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (size.isNotEmpty) ...[
              Text(size, style: TextStyle(fontSize: 11, color: onSub)),
              Text('  ·  ', style: TextStyle(fontSize: 11, color: onSub)),
            ],
            Text(ext.isNotEmpty ? '$ext Document' : 'Document', style: TextStyle(fontSize: 11, color: onSub)),
          ]),
        ]),
      ),
      const SizedBox(width: 8),
      Icon(Icons.file_download_outlined, color: widget.isMe ? Colors.white60 : AlanyaColors.grey500, size: 22),
    ]);
  }

  /// Ligne info fichier (icône + nom + taille).
  Widget _buildFileInfo(Color color, IconData icon, String ext, Color onText, Color onSub, String size) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(ext, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onText)),
      ),
    ]);
  }
}
