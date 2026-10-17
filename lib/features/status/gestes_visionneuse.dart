/// Les deux règles de geste de la visionneuse de statuts.
///
/// Elles sont pures — ni widget, ni contexte — donc vérifiables sans écran :
/// voir `test/anneau_statuts_test.dart`.
library;

/// Au-delà de cette durée, un appui n'est plus un tap : c'est un maintien.
///
/// 🔴 C'EST CE SEUIL QUI REMPLACE L'APPUI LONG. Avec un `onLongPress`, il
/// fallait tenir 500 ms pour que le défilement s'arrête — sur WhatsApp il
/// s'arrête dès que le doigt touche l'écran, et relâcher après un maintien ne
/// fait PAS avancer. Le doigt posé met donc en pause tout de suite, et c'est
/// la durée de l'appui, mesurée au relâchement, qui décide s'il s'agissait
/// d'un tap (on change de statut) ou d'un maintien (on reprend, sur place).
const Duration appuiCourtMax = Duration(milliseconds: 250);

/// Vrai si cet appui doit être compris comme un tap.
bool estAppuiCourt(Duration duree) => duree < appuiCourtMax;

/// Le tiers gauche de l'écran revient en arrière, le reste avance.
///
/// La zone « précédent » est volontairement la plus petite : on avance bien
/// plus souvent qu'on ne revient, et un retour déclenché par erreur rejoue un
/// statut qu'on venait de voir.
bool zonePrecedente(double dx, double largeur) {
  if (largeur <= 0) return false;
  return dx < largeur / 3;
}
