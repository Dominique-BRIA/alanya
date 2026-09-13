/// COMMENT RANGER LES VIGNETTES D'UN APPEL VIDÉO À PLUSIEURS.
///
/// 🔴 CE FICHIER EXISTE PARCE QUE L'ÉCRAN RESTAIT AUX TROIS QUARTS VIDE. La
/// grille d'avant imposait deux colonnes et un rapport hauteur / largeur fixe
/// de 0,85 : à deux participants, les deux vignettes se rangeaient en haut et
/// tout le bas de l'écran restait marron. C'est le défaut signalé par le user,
/// capture à l'appui.
///
/// ⚠️ ON RAISONNE EN RANGÉES, PAS EN COLONNES, et c'est la clé. Une grille à
/// colonnes fixes ne PEUT pas remplir la hauteur : le nombre de lignes y
/// découle du nombre d'éléments, et la dernière ligne reste incomplète. En
/// décrivant les rangées, chacune prend sa part de la hauteur et la dernière
/// s'étale sur toute la largeur quand elle est seule — ce que fait WhatsApp.
library;

/// Au-delà de ce nombre, aucune disposition fixe ne reste lisible : l'écran
/// bascule sur une grille qui défile.
///
/// ⚠️ MA PROPRE VIGNETTE COMPTE DANS CE TOTAL, comme chez WhatsApp : six tuiles
/// affichées, c'est donc cinq correspondants et moi.
const int maxVignettesSansDefilement = 6;

/// Combien de vignettes par rangée, pour [n] vignettes AFFICHÉES — les
/// correspondants plus moi-même, et non les seuls correspondants.
///
/// 🔴 LA SOMME DOIT TOUJOURS VALOIR [n]. L'écran découpe la liste des
/// participants rangée par rangée avec `sublist` : une somme trop grande sort
/// des bornes et lève en plein appel, une somme trop petite fait disparaître
/// quelqu'un de l'écran sans que rien ne le signale.
List<int> dispositionVignettes(int n) {
  switch (n) {
    case 1:
      return const [1];
    // Deux personnes : deux moitiés d'écran superposées. En colonnes, on
    // obtiendrait deux bandes verticales étroites — l'inverse du cadrage d'un
    // visage, qui est plus haut que large.
    case 2:
      return const [1, 1];
    // Trois : une grande au-dessus, deux au-dessous. Personne n'est réduit à
    // un tiers de bande.
    case 3:
      return const [1, 2];
    case 4:
      return const [2, 2];
    // Cinq : la dernière occupe toute la largeur plutôt que de laisser un trou
    // béant à côté d'elle.
    case 5:
      return const [2, 2, 1];
    default:
      return const [2, 2, 2];
  }
}
