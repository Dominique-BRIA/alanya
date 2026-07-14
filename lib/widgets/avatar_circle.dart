import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/server_config.dart';
import '../core/token_storage.dart';
import '../theme/app_theme.dart';
import 'auth_network_image.dart';

/// Avatar circulaire réutilisable partout dans l'app.
///
/// - Si [avatarUrl] est défini (chemin relatif /api/media/<id> OU URL absolue)
///   → charge la vraie photo via [AuthNetworkImage] (avec le token JWT).
/// - Sinon → affiche l'initiale de [name] sur fond [backgroundColor].
///
/// Utilisation :
/// ```dart
/// AvatarCircle(name: user.pseudo, avatarUrl: user.avatarUrl, radius: 24)
/// ```
class AvatarCircle extends StatefulWidget {
  const AvatarCircle({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.radius = 22,
    this.backgroundColor = AppColors.terracotta,
    this.textColor = Colors.white,
    this.borderColor,
    this.borderWidth = 0,
    this.onTap,
  });

  final String? name;
  final String? avatarUrl;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  @override
  State<AvatarCircle> createState() => _AvatarCircleState();
}

class _AvatarCircleState extends State<AvatarCircle> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    // Utilisé uniquement pour AuthNetworkImage (GET /api/media/<id> requiert le token).
    // On lit une fois, pas de refresh nécessaire (le token vit longtemps).
    try {
      final t = await context.read<TokenStorage>().accessToken;
      if (mounted) setState(() => _token = t);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        (widget.name?.trim().isNotEmpty ?? false) ? widget.name!.trim()[0].toUpperCase() : "?";
    final size = widget.radius * 2;

    // Reconstruit l'URL absolue si avatarUrl est un chemin relatif.
    String? fullUrl;
    final raw = widget.avatarUrl;
    if (raw != null && raw.isNotEmpty) {
      fullUrl = raw.startsWith("http") ? raw : "${ServerConfig.apiBase}$raw";
    }

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.backgroundColor,
        border: widget.borderColor != null
            ? Border.all(color: widget.borderColor!, width: widget.borderWidth)
            : null,
      ),
      child: ClipOval(
        child: fullUrl != null && _token != null
            ? AuthNetworkImage(
                url: fullUrl,
                token: _token,
                width: size,
                height: size,
                fit: BoxFit.cover,
              )
            : Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: widget.radius * 0.9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );

    if (widget.onTap != null) {
      content = InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: content,
      );
    }
    return content;
  }
}
