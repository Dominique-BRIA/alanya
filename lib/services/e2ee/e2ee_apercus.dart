import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// LES APERÇUS D'UN MÉDIA CHIFFRÉ — fabriqués par l'EXPÉDITEUR. Jumeau de
/// `STAGE-WEB/src/services/e2ee-apercus.ts` (cours, chapitres 24 et 25).
///
/// Le serveur n'a que des octets illisibles : c'est l'expéditeur, qui a le
/// fichier en clair, qui fabrique l'aperçu ; il voyage dans l'enveloppe.
///
/// ⚠️ L'APERÇU D'UNE PHOTO EST UN PNG, PAS UN JPEG. Flutter ne sait pas
/// encoder du JPEG sans ajouter une dépendance (trois chaînes de CI à tenir
/// accordées). Un PNG de 32 px pèse ~2 Ko : la différence est sans effet, et
/// le web reconnaît le format à ses premiers octets.
///
/// ⚠️ PLAFONNÉ (une enveloppe ne dépasse pas 64 Ko) et JAMAIS BLOQUANT : un
/// aperçu raté laisse partir le média sans aperçu.
class Apercu {
  const Apercu({
    this.apercu,
    this.largeur,
    this.hauteur,
    this.dureeMs,
    this.pages,
  });
  final String? apercu;
  final int? largeur;
  final int? hauteur;
  final int? dureeMs;
  final int? pages;
}

const _apercuMax = 40000;

Future<Apercu> fabriquerApercu(
  Uint8List octets,
  String mime, {
  String? chemin,
  int? dureeMs,
}) async {
  try {
    if (mime.startsWith('image/')) return await _image(octets);
    if (mime.startsWith('video/')) return await _video(octets, chemin, dureeMs);
    if (mime.startsWith('audio/')) return Apercu(dureeMs: dureeMs);
    if (mime == 'application/pdf') return await _pdf(octets);
  } catch (e) {
    debugPrint('[e2ee] aperçu impossible, le média part sans : $e');
  }
  return Apercu(dureeMs: dureeMs);
}

/// Une photo : ses dimensions, et une mini-image de 32 px, floutée à
/// l'affichage. Ce sont surtout les DIMENSIONS qui comptent : la bulle prend
/// sa taille d'emblée.
Future<Apercu> _image(Uint8List octets) async {
  final dims = await _dimensions(octets);
  if (dims == null) return const Apercu();
  final (l, h) = dims;
  final petite = await _reduire(octets, l, h, 32);
  return Apercu(largeur: l, hauteur: h, apercu: petite);
}

/// Une vidéo : sa première image, nette (~320 px), et sa durée.
Future<Apercu> _video(Uint8List octets, String? chemin, int? dureeMs) async {
  var fichier = chemin;
  File? temporaire;
  if (fichier == null || !File(fichier).existsSync()) {
    final dossier = await getTemporaryDirectory();
    temporaire = File(
      '${dossier.path}/apercu-${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await temporaire.writeAsBytes(octets, flush: true);
    fichier = temporaire.path;
  }
  try {
    final image = await VideoThumbnail.thumbnailData(
      video: fichier,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 320,
      quality: 60,
    );
    var duree = dureeMs;
    if (duree == null) {
      final c = VideoPlayerController.file(File(fichier));
      try {
        await c.initialize();
        duree = c.value.duration.inMilliseconds;
      } finally {
        await c.dispose();
      }
    }
    if (image == null) return Apercu(dureeMs: duree);
    final dims = await _dimensions(image);
    final b64 = base64Encode(image);
    return Apercu(
      largeur: dims?.$1,
      hauteur: dims?.$2,
      dureeMs: duree,
      apercu: b64.length <= _apercuMax ? b64 : null,
    );
  } finally {
    if (temporaire != null && temporaire.existsSync())
      await temporaire.delete();
  }
}

/// Un PDF : sa première page (~160 px) et son nombre de pages.
Future<Apercu> _pdf(Uint8List octets) async {
  final doc = await PdfDocument.openData(octets);
  try {
    final pages = doc.pagesCount;
    final page = await doc.getPage(1);
    try {
      final echelle =
          160 / (page.width > page.height ? page.width : page.height);
      final rendu = await page.render(
        width: page.width * echelle,
        height: page.height * echelle,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 60,
      );
      final b64 = rendu == null ? null : base64Encode(rendu.bytes);
      return Apercu(
        pages: pages,
        apercu: b64 != null && b64.length <= _apercuMax ? b64 : null,
      );
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

Future<(int, int)?> _dimensions(Uint8List octets) async {
  final codec = await ui.instantiateImageCodec(octets);
  try {
    final trame = await codec.getNextFrame();
    final r = (trame.image.width, trame.image.height);
    trame.image.dispose();
    return r;
  } finally {
    codec.dispose();
  }
}

/// Réduit à [cote] px sur le plus grand côté, en PNG.
Future<String?> _reduire(Uint8List octets, int l, int h, int cote) async {
  final codec = await ui.instantiateImageCodec(
    octets,
    targetWidth: l >= h ? cote : null,
    targetHeight: h > l ? cote : null,
  );
  try {
    final trame = await codec.getNextFrame();
    final donnees = await trame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    trame.image.dispose();
    if (donnees == null) return null;
    final b64 = base64Encode(donnees.buffer.asUint8List());
    return b64.length <= _apercuMax ? b64 : null;
  } finally {
    codec.dispose();
  }
}
