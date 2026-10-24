import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/media_cache.dart';

/// L'IMAGE D'UN STICKER, gardée sur l'appareil : un sticker vu une fois ne
/// se retélécharge plus, même après un redémarrage (WhatsApp fait pareil).
///
/// ⚠️ SA PROPRE CLÉ DE CACHE (`sticker-<url>`) : `CachedMedia` range par
/// dernier segment d'URL, et `/api/stickers/fichier/40` y croiserait un
/// autre fichier numéroté 40.
///
/// Les images sont servies sans jeton : un sticker publié est public.
class ImageSticker extends StatefulWidget {
  const ImageSticker({super.key, required this.url, this.taille = 72});

  final String url;
  final double taille;

  @override
  State<ImageSticker> createState() => _ImageStickerState();
}

/// Les téléchargements en cours, partagés : une grille de quarante stickers
/// identiques n'en lance qu'un.
final Map<String, Future<String?>> _enCours = {};

String _cle(String url) =>
    'sticker-${url.hashCode.toUnsigned(32).toRadixString(16)}';

Future<String?> _chemin(String url) {
  return _enCours.putIfAbsent(url, () async {
    try {
      return await MediaCache.getOrFetch(
        mediaId: _cle(url),
        ext: 'img',
        fetchNetwork: () async {
          final r = await http.get(Uri.parse(url));
          if (r.statusCode != 200) throw HttpException('${r.statusCode}');
          return r.bodyBytes;
        },
      );
    } catch (_) {
      // Retiré par la modération (410), hors ligne : on réessaiera plus tard.
      _enCours.remove(url);
      return null;
    }
  });
}

class _ImageStickerState extends State<ImageSticker> {
  late Future<String?> _fichier = _chemin(widget.url);

  @override
  void didUpdateWidget(ImageSticker ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.url != widget.url) _fichier = _chemin(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.taille,
      child: FutureBuilder<String?>(
        future: _fichier,
        builder: (context, s) {
          final chemin = s.data;
          if (chemin != null) {
            return Image.file(
              File(chemin),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const _Absent(),
            );
          }
          if (s.connectionState == ConnectionState.done) return const _Absent();
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _Absent extends StatelessWidget {
  const _Absent();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.broken_image_outlined,
    color: Theme.of(context).disabledColor,
  );
}
