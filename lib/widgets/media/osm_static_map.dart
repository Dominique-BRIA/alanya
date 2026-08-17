import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';

/// Carte statique centrée sur un point, composée de tuiles.
///
/// POURQUOI À LA MAIN, sans paquet de cartographie : `flutter_map` ferait
/// exactement cela en beaucoup plus gros, et **ajouter un paquet, c'est toucher
/// à tous les environnements de build** — il y a trois CI dans ce projet, plus
/// le poste local, et une contrainte `environment:` incompatible casse le
/// `pub get` de l'un d'eux sans que rien ne le signale ici. Une carte figée
/// n'a besoin ni de gestes, ni de couches, ni de plugins : seulement de la
/// projection de Mercator et de quelques images.
///
/// 🔴 **AVANT PUBLICATION SUR LE PLAY STORE, TRANCHER LA SOURCE DES TUILES.**
/// La politique d'usage d'openstreetmap.org interdit qu'une application
/// DISTRIBUÉE tire ses tuiles directement de leurs serveurs. Trois issues, et
/// une seule ligne à changer ([_baseTuiles]) :
///   1. une clé chez un fournisseur (MapTiler, Geoapify… ont un palier gratuit) ;
///   2. un relais par notre backend, qui met les tuiles en cache ;
///   3. renoncer aux tuiles et garder la carte schématique.
/// L'en-tête `User-Agent` identifie l'application, comme leur politique
/// l'exige, mais cela ne suffit pas à autoriser une distribution publique.
class OsmStaticMap extends StatelessWidget {
  const OsmStaticMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.width,
    required this.height,
    this.zoom = 15,
    this.marqueur = true,
  });

  final double lat;
  final double lng;
  final double width;
  final double height;
  final int zoom;
  final bool marqueur;

  /// Source des tuiles — voir l'avertissement de l'en-tête de classe.
  static const String _baseTuiles = "https://tile.openstreetmap.org";

  /// Exigé par la politique d'usage : une application anonyme est bloquée.
  static const Map<String, String> _entetes = {
    "User-Agent": "AlanyaWork/0.1 (com.alanya237.work)",
  };

  static const double _tuile = 256;

  static double _xMonde(double lon, int z) =>
      (lon + 180.0) / 360.0 * _tuile * (1 << z);

  static double _yMonde(double lat, int z) {
    // Mercator : la latitude n'est pas linéaire. Bornée à ±85,05° — au-delà, la
    // projection part à l'infini (et il n'y a pas de tuiles aux pôles).
    final borne = lat.clamp(-85.05112878, 85.05112878);
    final rad = borne * pi / 180.0;
    return (1 - log(tan(rad) + 1 / cos(rad)) / pi) / 2 * _tuile * (1 << z);
  }

  @override
  Widget build(BuildContext context) {
    final centreX = _xMonde(lng, zoom);
    final centreY = _yMonde(lat, zoom);

    // Coin haut-gauche de la fenêtre, en pixels monde.
    final origineX = centreX - width / 2;
    final origineY = centreY - height / 2;

    const tuileMin = 0;
    final tuileMax = (1 << zoom) - 1;
    final xDebut = (origineX / _tuile).floor();
    final yDebut = (origineY / _tuile).floor();
    final xFin = ((origineX + width) / _tuile).floor();
    final yFin = ((origineY + height) / _tuile).floor();

    final images = <Widget>[];
    for (var tx = xDebut; tx <= xFin; tx++) {
      for (var ty = yDebut; ty <= yFin; ty++) {
        // Hors du monde en latitude : il n'existe aucune tuile, on laisse le
        // fond. En longitude, on enroule (le monde est un cylindre).
        if (ty < tuileMin || ty > tuileMax) continue;
        final txEnroule = tx % (1 << zoom);
        final x = (txEnroule < 0 ? txEnroule + (1 << zoom) : txEnroule);
        images.add(Positioned(
          left: tx * _tuile - origineX,
          top: ty * _tuile - origineY,
          width: _tuile,
          height: _tuile,
          child: Image.network(
            "$_baseTuiles/$zoom/$x/$ty.png",
            headers: _entetes,
            fit: BoxFit.cover,
            // Une tuile manquante ne doit pas trouer la carte : le fond neutre
            // reste visible, et le repère par-dessus dit toujours où on est.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            loadingBuilder: (_, enfant, progres) =>
                progres == null ? enfant : const SizedBox.shrink(),
          ),
        ));
      }
    }

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fond visible tant que les tuiles chargent, et sous les trous.
            Container(color: const Color(0xFFE8E4DC)),
            ...images,
            if (marqueur)
              Center(
                child: Padding(
                  // La pointe du repère doit tomber SUR le point, pas son
                  // centre : on le remonte de la moitié de sa hauteur.
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Icon(Icons.location_pin,
                      size: 36,
                      color: const Color(0xFFEF4444),
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1)),
                      ]),
                ),
              ),
            // Attribution : la licence des données l'exige, même sur une
            // vignette.
            Positioned(
              right: 3,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                color: Colors.white.withValues(alpha: 0.7),
                child: const Text("© OpenStreetMap",
                    style: TextStyle(fontSize: 7, color: AlanyaColors.ink)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
