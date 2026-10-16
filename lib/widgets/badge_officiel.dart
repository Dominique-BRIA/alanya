import 'package:flutter/material.dart';

import '../theme/alanya_theme.dart';

/// Le badge du compte officiel « Alanya Work », à côté de son nom.
///
/// Coche au vert du logo sur une pastille blanche : la pastille garde le
/// badge lisible sur toutes les surfaces — liste claire ou nuit, en-tête
/// coloré du fil.
class BadgeOfficiel extends StatelessWidget {
  const BadgeOfficiel({super.key, this.taille = 16});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Compte officiel',
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.verified, size: taille, color: AlanyaColors.logoVert),
      ),
    );
  }
}
