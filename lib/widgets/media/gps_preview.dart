import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';
import 'location_bubble.dart';
import 'osm_static_map.dart';

class GpsCoords {
  final double lat;
  final double lng;
  const GpsCoords({required this.lat, required this.lng});
}

/// Coordonnées reconnues DANS UN MESSAGE TEXTE, ou `null`.
///
/// Sert aux messages que d'autres producteurs envoient en TEXT — l'annonce
/// commerciale d'un vendeur, par exemple, avec le point de vente entre
/// parenthèses. Un partage de position fait depuis cette application est
/// désormais un vrai message `LOCATION` et ne passe pas par ici.
///
/// 🔴 **UN COUPLE DE DÉCIMAUX NU N'EST PLUS RECONNU, et c'est une correction.**
/// La règle d'avant acceptait `(-?\d+\.\d{2,})\s*,\s*(-?\d+\.\d{2,})` n'importe
/// où dans le texte : « j'ai payé 12.50, 30.75 » affichait donc une carte au
/// Soudan, et — pire — l'écran de discussion RETIRE du texte affiché ce qui a
/// été reconnu, si bien que le message perdait ses montants. Les bornes seules
/// ne suffisaient pas : ces deux nombres sont des coordonnées valides.
///
/// Il faut maintenant une marque explicite :
///   - des parenthèses : `… au centre-ville ! (3.8480, 11.5020)` ;
///   - un lien de carte Google ;
///   - une URI `geo:3.8480,11.5020`.
///
/// Les bornes sont vérifiées en plus : `1500.50, 2300.75` n'est de toute façon
/// pas un point de la Terre.
GpsCoords? extractGpsCoords(String text) {
  GpsCoords? valide(String? a, String? b) {
    if (a == null || b == null) return null;
    final lat = double.tryParse(a);
    final lng = double.tryParse(b);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return GpsCoords(lat: lat, lng: lng);
  }

  final gmaps = RegExp(
      r'(?:google\.\w+/maps|maps\.google\.\w+|goo\.gl/maps).*?[/@](-?\d+\.\d+),(-?\d+\.\d+)');
  final gm = gmaps.firstMatch(text);
  if (gm != null) {
    final r = valide(gm.group(1), gm.group(2));
    if (r != null) return r;
  }

  final geoUri = RegExp(r'geo:\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
  final gu = geoUri.firstMatch(text);
  if (gu != null) {
    final r = valide(gu.group(1), gu.group(2));
    if (r != null) return r;
  }

  final entreParentheses =
      RegExp(r'\(\s*(-?\d+\.\d{2,})\s*,\s*(-?\d+\.\d{2,})\s*\)');
  final ep = entreParentheses.firstMatch(text);
  if (ep != null) {
    final r = valide(ep.group(1), ep.group(2));
    if (r != null) return r;
  }

  return null;
}

/// Carte compacte affichée SOUS un message texte porteur de coordonnées.
///
/// Pour un vrai message `LOCATION`, c'est [LocationBubble] qui s'affiche.
class GpsPreview extends StatelessWidget {
  final double lat;
  final double lng;
  final bool isMe;

  const GpsPreview({
    super.key,
    required this.lat,
    required this.lng,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onSub =
        isMe ? Colors.white70 : (dark ? AlanyaColors.craie2 : Colors.black54);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => ouvrirCarteExterne(lat, lng),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 226,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              OsmStaticMap(lat: lat, lng: lng, width: 226, height: 108),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.location_on,
                    size: 14,
                    color: isMe ? Colors.white : const Color(0xFFEF4444)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: onSub),
                  ),
                ),
                Icon(Icons.open_in_new, size: 12, color: onSub),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
