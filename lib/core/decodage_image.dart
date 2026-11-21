import 'package:flutter/widgets.dart';

/// À QUELLE LARGEUR DÉCODER UNE IMAGE AFFICHÉE EN PETIT (21/11/2026).
///
/// Flutter décode une image à sa taille d'ORIGINE, quelle que soit la place
/// qu'elle occupe à l'écran : une photo de 12 Mpx coûte près de 50 Mo en
/// mémoire, même dans une bulle de 250 points. Une discussion pleine de photos
/// en « Meilleure qualité » faisait ainsi fermer l'application sur un
/// téléphone modeste. Décoder à la largeur affichée (en pixels réels) suffit
/// à l'œil et divise la mémoire par dix ou plus.
///
/// ⚠️ PAS POUR LES VISIONNEUSES PLEIN ÉCRAN : on y zoome, la pleine
/// résolution y est voulue — et il n'y a qu'une image à la fois.

/// [largeur] en points → pixels réels de l'écran ; `null` (taille d'origine)
/// quand la largeur n'est pas connue.
int? largeurDecodage(BuildContext context, double? largeur) {
  if (largeur == null || !largeur.isFinite || largeur <= 0) return null;
  return (largeur * MediaQuery.devicePixelRatioOf(context)).round();
}

/// Pour une bulle de discussion : au plus les quatre cinquièmes de l'écran.
int largeurDecodageBulle(BuildContext context) =>
    largeurDecodage(context, MediaQuery.sizeOf(context).width * 0.8) ?? 1080;
