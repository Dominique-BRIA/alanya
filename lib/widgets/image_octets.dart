import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Ces octets sont-ils du SVG ?
///
/// Le SVG est du XML, il n'a donc pas de nombre magique comme JPEG ou PNG. On
/// cherche la balise racine dans le début du flux, ce qui couvre aussi bien
/// `<svg …>` seul qu'un document précédé d'un prologue `<?xml …?>`, d'un
/// commentaire ou d'un DOCTYPE.
bool estSvg(Uint8List octets) {
  if (octets.length < 4) return false;
  // 512 octets suffisent : au-delà, le prologue serait anormalement long, et
  // décoder tout un fichier pour un test de type coûterait cher sur une liste.
  final debut = octets.length < 512 ? octets : octets.sublist(0, 512);
  // `latin1` plutôt qu'`utf8` : ne lève jamais sur des octets binaires, alors
  // qu'un JPEG ferait échouer le décodage UTF-8.
  final texte = String.fromCharCodes(debut).toLowerCase();
  return texte.contains("<svg");
}

/// Affiche des octets d'image, **SVG compris**.
///
/// Flutter n'affiche nativement aucun SVG : `Image.memory` ne reconnaît que
/// JPEG, PNG, GIF et WebP. Sans ce point de passage, les avatars générés que
/// l'équipe pose depuis son backend (`api.dicebear.com/…/svg`) restaient
/// invisibles — rejetés avant même d'être décodés.
///
/// [surErreur] est appelé quand les octets ne forment aucune image lisible :
/// l'appelant décide alors quoi montrer, une initiale ou un repli.
Widget imageDepuisOctets(
  Uint8List octets, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function()? surErreur,
  Key? key,
}) {
  final repli = surErreur ?? () => const SizedBox.shrink();
  final widgetKey = key ?? ValueKey(octets);

  if (estSvg(octets)) {
    return SvgPicture.memory(
      octets,
      key: widgetKey,
      width: width,
      height: height,
      fit: fit,
      // Un SVG malformé ne doit pas casser l'écran qui l'affiche : la donnée
      // vient d'une autre application, et nous n'en maîtrisons pas la qualité.
      placeholderBuilder: (_) => repli(),
    );
  }

  return Image.memory(
    octets,
    key: widgetKey,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) => repli(),
  );
}
