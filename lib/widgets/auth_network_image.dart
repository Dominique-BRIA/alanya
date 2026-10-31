import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'image_octets.dart';
import 'media/cached_media.dart';
import '../l10n/app_localizations.dart';

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
    this.onCharge,
    this.onEchec,
    this.pendant,
  });

  final String url;
  final String? token;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Appelé dès que l'image est affichable.
  ///
  /// Ajouté pour la visionneuse de statuts : sa barre de progression ne doit
  /// pas courir pendant le téléchargement, sinon une photo lente est passée
  /// avant d'être apparue. Le widget ne disait rien de son chargement, il n'y
  /// avait donc rien à attendre.
  final VoidCallback? onCharge;

  /// Appelé quand l'image ne sera jamais affichable (jeton absent, refus du
  /// serveur, octets illisibles). Sans lui, celui qui attend l'image
  /// attendrait pour toujours.
  final VoidCallback? onEchec;

  /// Ce qui s'affiche tant que l'image n'est pas là, ou si elle ne vient pas.
  /// Un avatar y met son initiale : un cercle de chargement dans un rond de
  /// quarante pixels, puis la photo, c'était un clignotement de plus.
  final Widget? pendant;

  /*
   * LES PETITES IMAGES DÉJÀ LUES RESTENT EN MÉMOIRE (01/11/2026) : photos de
   * profil, vignettes. Le cache disque les gardait, mais chaque nouvel avatar
   * — une ligne qui revient à l'écran, une conversation rouverte — attendait
   * la lecture du fichier avant de s'afficher. Les grosses images n'y entrent
   * pas : la mémoire n'est pas faite pour elles.
   */
  static const _tailleMaxMemoire = 400 * 1024;
  static const _entreesMax = 150;
  static final Map<String, Uint8List> _memoire = {};

  static void _retenir(String url, Uint8List octets) {
    if (octets.length > _tailleMaxMemoire) return;
    _memoire.remove(url);
    _memoire[url] = octets;
    if (_memoire.length > _entreesMax) _memoire.remove(_memoire.keys.first);
  }

  @override
  State<AuthNetworkImage> createState() => _AuthNetworkImageState();
}

class _AuthNetworkImageState extends State<AuthNetworkImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final connu = AuthNetworkImage._memoire[widget.url];
    if (connu != null) {
      // Déjà lue : affichée au premier tracé, sans rien relire.
      _bytes = connu;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCharge?.call());
      return;
    }
    _load();
  }

  @override
  void didUpdateWidget(AuthNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = AuthNetworkImage._memoire[widget.url];
      _error = false;
      if (_bytes == null) _load();
    } else if (old.token != widget.token && _bytes == null) {
      // ⚠️ UN JETON RAFRAÎCHI NE RECHARGE PAS UNE IMAGE DÉJÀ LÀ : elle ne
      // dépend que de son adresse. Recharger la faisait disparaître un instant.
      _error = false;
      _load();
    }
  }

  static bool _looksLikeImage(Uint8List bytes, String? contentType) {
    if (contentType != null && contentType.startsWith("image/")) return true;
    if (bytes.length < 4) return false;
    // Le SVG n'a pas de nombre magique : il est reconnu a part, sur sa
    // balise racine. Sans ce cas, les avatars generes par l'equipe
    // (dicebear renvoie du SVG) etaient rejetes ici meme, avant affichage.
    if (estSvg(bytes)) return true;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
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
      widget.onEchec?.call();
      return;
    }
    try {
      // Passe par le cache disque persistant : téléchargé une seule fois.
      final bytes = await loadCachedMediaBytes(widget.url, token);
      if (!mounted) return;
      if (bytes != null && _looksLikeImage(bytes, null)) {
        AuthNetworkImage._retenir(widget.url, bytes);
        setState(() {
          _bytes = bytes;
          _error = false;
        });
        widget.onCharge?.call();
      } else {
        setState(() => _error = true);
        widget.onEchec?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
      widget.onEchec?.call();
    }
  }

  Widget _errorPlaceholder() {
    final pendant = widget.pendant;
    if (pendant != null) return pendant;
    return Container(
      width: widget.width,
      height: widget.height ?? 120,
      color: Colors.black12,
      alignment: Alignment.center,
      child: Text(tr(context, 'image_unavailable'), style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = imageDepuisOctets(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        surErreur: _errorPlaceholder,
      );
    } else if (_error) {
      child = _errorPlaceholder();
    } else {
      child = widget.pendant ??
          SizedBox(
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
