import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Charge une image protégée par JWT (Bearer) puis l'affiche en mémoire.
/// Évite d'exposer le token dans l'URL et gère mieux les erreurs 401.
class AuthNetworkImage extends StatefulWidget {
  const AuthNetworkImage({
    super.key,
    required this.url,
    required this.token,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String url;
  final String? token;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<AuthNetworkImage> createState() => _AuthNetworkImageState();
}

class _AuthNetworkImageState extends State<AuthNetworkImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuthNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.token != widget.token) {
      _bytes = null;
      _error = false;
      _load();
    }
  }

  static bool _looksLikeImage(Uint8List bytes, String? contentType) {
    if (contentType != null && contentType.startsWith("image/")) return true;
    if (bytes.length < 4) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    // GIF
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return true;
    }
    // WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _error = true);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse(widget.url),
        headers: {"Authorization": "Bearer $token"},
      );
      if (!mounted) return;
      if (res.statusCode == 200 && _looksLikeImage(res.bodyBytes, res.headers["content-type"])) {
        setState(() {
          _bytes = res.bodyBytes;
          _error = false;
        });
      } else {
        setState(() => _error = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Widget _errorPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height ?? 120,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Text("Image indisponible", style: TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _errorPlaceholder(),
      );
    } else if (_error) {
      child = _errorPlaceholder();
    } else {
      child = SizedBox(
        width: widget.width,
        height: widget.height ?? 200,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}
