import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/token_storage.dart';
import '../../../widgets/avatar_source.dart';

/// Visualiseur de photo de profil plein écran (style WhatsApp).
///
/// Fonctionnalités :
///  - Fond noir immersif
///  - Zoom pinch (via InteractiveViewer)
///  - Swipe vertical pour fermer
///  - Nom affiché en haut avec bouton retour
///  - Si aucune photo → affiche l'initiale en grand
class AvatarViewerScreen extends StatefulWidget {
  const AvatarViewerScreen({
    super.key,
    required this.name,
    required this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;

  @override
  State<AvatarViewerScreen> createState() => _AvatarViewerScreenState();
}

class _AvatarViewerScreenState extends State<AvatarViewerScreen> {
  String? _token;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final t = await context.read<TokenStorage>().accessToken;
      if (mounted) setState(() => _token = t);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Trois formes coexistent en base, dont des images base64 ecrites par
    // l'application de l'equipe sur la base partagee. Voir [AvatarSource].
    final photo = AvatarSource.depuis(widget.avatarUrl)
        .image(token: _token, fit: BoxFit.contain);

    // Opacité du fond diminue avec le swipe (feedback visuel).
    final bgOpacity = (1.0 - (_dragOffset.abs() / 400)).clamp(0.0, 1.0);
    final initial = widget.name.trim().isNotEmpty
        ? widget.name.trim()[0].toUpperCase()
        : "?";

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(bgOpacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(bgOpacity * 0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.name,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      body: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => _dragOffset += d.delta.dy),
        onVerticalDragEnd: (_) {
          if (_dragOffset.abs() > 100) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Center(
            child: photo != null
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: photo,
                  )
                : Container(
                    width: 240,
                    height: 240,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFCB6E45), // AlanyaColors.terracotta hex
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 120,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
