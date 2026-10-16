import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/badge_compte.dart';

/// Dessine le badge envoyé par le serveur à côté d'un nom — et rien d'autre.
///
/// L'image et le libellé viennent de la charge (`badge`) : les changer se fait
/// depuis la console, sans nouvelle version de l'application. Image
/// injoignable : rien ne s'affiche, le nom reste lisible.
class BadgeCompteWidget extends StatelessWidget {
  const BadgeCompteWidget(this.badge, {super.key, this.taille = 16});

  final BadgeCompte badge;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final rien = SizedBox(width: 0, height: taille);
    final image = badge.image.toLowerCase().split('?').first.endsWith('.svg')
        ? SvgPicture.network(badge.image,
            width: taille, height: taille, placeholderBuilder: (_) => rien)
        : Image.network(badge.image,
            width: taille,
            height: taille,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => rien);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: badge.libelle.isEmpty
          ? image
          : Tooltip(message: badge.libelle, child: image),
    );
  }
}
