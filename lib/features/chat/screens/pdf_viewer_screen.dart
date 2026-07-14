import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/downloader.dart';
import '../../../theme/app_theme.dart';

/// Visionneuse PDF plein écran (style WhatsApp).
///
/// Fonctionnalités :
///  - Charge le PDF dans un fichier local temporaire (nécessaire pour la lib
///    native), garde le fichier en cache app pour rouvrir instantanément.
///  - Navigation par pages, affichage du n° page courant.
///  - Bouton téléchargement dans la bar (sauvegarde dans Alanya/ public).
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.downloadUrl,
    required this.filename,
  });

  final String pdfUrl;
  final String downloadUrl;
  final String filename;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  String? _error;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // 1) Vérifie le cache app-privé (rouverture instantanée si déjà téléchargé).
    final cached = await getCachedFile(widget.filename);
    if (cached != null && mounted) {
      setState(() => _localPath = cached);
      return;
    }
    // 2) Télécharge dans le cache app-privé (pas dans le stockage public).
    final path = await downloadToCache(widget.pdfUrl, widget.filename);
    if (!mounted) return;
    if (path == null) {
      setState(() => _error = "Impossible de charger le PDF");
    } else {
      setState(() => _localPath = path);
    }
  }

  Future<void> _saveToPublic() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final path = await downloadUrl(widget.downloadUrl, widget.filename);
      if (!mounted) return;
      showAppSnackBar(path != null
          ? "Enregistré dans Alanya/"
          : "Échec du téléchargement");
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.filename,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "${_currentPage + 1}/$_totalPages",
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          IconButton(
            tooltip: "Télécharger",
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            onPressed: _downloading ? null : _saveToPublic,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 60),
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.terracotta,
                    ),
                    onPressed: _saveToPublic,
                    icon: const Icon(Icons.download),
                    label: const Text("Télécharger quand même"),
                  ),
                ],
              ),
            )
          : _localPath == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.terracotta),
                )
              : PDFView(
                  filePath: _localPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  pageSnap: true,
                  fitPolicy: FitPolicy.WIDTH,
                  onRender: (pages) {
                    if (mounted) setState(() => _totalPages = pages ?? 0);
                  },
                  onPageChanged: (page, _) {
                    if (mounted) setState(() => _currentPage = page ?? 0);
                  },
                  onError: (e) {
                    if (mounted) setState(() => _error = "Erreur : $e");
                  },
                ),
    );
  }
}
