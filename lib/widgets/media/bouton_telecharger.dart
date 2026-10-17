import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';
import '../../l10n/app_localizations.dart';

/// LE BOUTON « TÉLÉCHARGER » DES LECTEURS DE MÉDIAS, en haut à droite.
///
/// 🐛 « LE BOUTON TÉLÉCHARGEMENT DES MÉDIAS A DISPARU : CHOISIS UNE COULEUR
/// VISIBLE, À DROITE EN HAUT » (user, 06/10/2026). Une icône blanche nue se
/// perdait sur une photo claire ; elle était en plus retirée pour les médias
/// chiffrés. Une pastille pleine, terre cuite, se voit sur tous les fonds.
///
/// Un seul widget pour les quatre lecteurs (galerie, image, vidéo, PDF) : la
/// même place et la même couleur partout.
class BoutonTelecharger extends StatelessWidget {
  const BoutonTelecharger({
    super.key,
    required this.enCours,
    required this.onPressed,
  });

  /// Un téléchargement est en cours : l'anneau remplace l'icône.
  final bool enCours;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IconButton.filled(
          tooltip: tr(context, 'download'),
          style: IconButton.styleFrom(
            backgroundColor: AlanyaColors.terracotta,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AlanyaColors.terracotta,
          ),
          onPressed: enCours ? null : onPressed,
          icon: enCours
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download_rounded),
        ),
      );
}
