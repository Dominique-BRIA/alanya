import 'package:flutter/material.dart';

import '../../theme/alanya_theme.dart';

/// La teinte d'une liste de contacts.
///
/// 🔴 **CINQ NOMS, ET C'EST UN CONTRAT PARTAGÉ AVEC LE WEB.** La colonne
/// `contactList.color` est une chaîne libre côté serveur, mais le web n'y écrit
/// que ces cinq valeurs — voir `contact-lists-affichage.ts`, dont le commentaire
/// dit explicitement : « la couleur est rangée sous le NOM de sa teinte (`blue`)
/// et non sous la variable CSS qui la dessine : le champ est partagé avec
/// l'application mobile, qui ne connaît pas les variables du web ».
///
/// ⚠️ Ma première version ne lisait que l'hexadécimal : elle aurait affiché la
/// couleur d'accent par défaut pour **toute liste créée depuis le web**, sans
/// que rien ne le signale. C'est exactement la divergence entre clients que ce
/// projet paie régulièrement.
///
/// Les valeurs mobiles ne copient pas les hexadécimaux du web — les siens
/// changent avec son thème. Seul le NOM voyage ; chaque client le dessine avec
/// sa propre palette.

/// L'ordre de la palette proposée à la création, identique au web.
///
/// 🔴 **VINGT TEINTES EN HEXADÉCIMAL, ET NON PLUS CINQ NOMS.**
///
/// Cinq ne suffisaient pas : au-delà de cinq listes, deux portaient forcément la
/// même pastille. Le rouge manquait, alors que c'est la teinte qu'on cherche en
/// premier pour une liste qui compte.
///
/// ⚠️ Le web a basculé sur ces mêmes valeurs hexadécimales
/// (`contact-lists-affichage.ts`, `PALETTE_LISTES`). Garder les cinq NOMS ici
/// aurait fait diverger les deux clients : une liste créée sur mobile aurait
/// porté « blue », une liste créée sur le web « #1e88e5 », et les deux se
/// seraient dessinées différemment sur le même écran.
///
/// Les noms restent LUS par [couleurDeListe] — les listes déjà créées avec
/// « amber » continuent de s'afficher. Ils ne sont simplement plus PROPOSÉS.
const List<String> paletteListes = [
  // L'arc-en-ciel, dans son ordre.
  "#e53935", // rouge
  "#f4511e", // vermillon
  "#fb8c00", // orange
  "#fdd835", // jaune
  "#c0ca33", // citron
  "#7cb342", // vert clair
  "#43a047", // vert
  "#00897b", // sarcelle
  "#00acc1", // cyan
  "#039be5", // bleu ciel
  "#1e88e5", // bleu
  "#3949ab", // indigo
  "#5e35b1", // violet
  "#8e24aa", // pourpre
  "#d81b60", // magenta
  // Quelques teintes sourdes, pour les listes qu'on ne veut pas voir crier.
  "#6d4c41", // brun
  "#546e7a", // ardoise
  "#795548", // terre
  "#8d6e63", // taupe
  "#607d8b", // gris bleu
];

/// La couleur à peindre pour une teinte nommée.
///
/// Rend `null` — et non une couleur de repli — quand la valeur est inconnue :
/// c'est l'appelant qui décide quoi mettre à la place, et lui seul connaît le
/// thème courant.
///
/// Accepte aussi un hexadécimal (`#RRGGBB`), comme le web : une valeur posée
/// par un troisième client ne doit pas être perdue.
Color? couleurDeListe(String? teinte, {required bool sombre}) {
  if (teinte == null) return null;
  final nom = teinte.trim().toLowerCase();

  switch (nom) {
    case "amber":
      return sombre ? AlanyaColors.goldLight : AlanyaColors.gold;
    case "blue":
      return sombre ? AlanyaColors.indigoLight : AlanyaColors.bleuAppel;
    case "violet":
      return sombre ? AlanyaColors.indigoLight : AlanyaColors.indigo;
    case "teal":
      return sombre ? AlanyaColors.forestLight : AlanyaColors.forest;
    case "rose":
      return sombre
          ? AlanyaColors.terracottaNuitLight
          : AlanyaColors.terracottaLight;
  }

  // Repli hexadécimal, pour ne pas perdre une valeur venue d'ailleurs.
  final propre = nom.replaceAll("#", "");
  if (propre.length != 6) return null;
  final v = int.tryParse(propre, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Le nom lisible d'une teinte, pour l'accessibilité et les info-bulles.
///
/// Les cinq NOMS historiques gardent leur libellé — des listes en portent
/// encore. Les vingt teintes hexadécimales n'en ont pas : nommer vingt couleurs
/// dans neuf langues serait un catalogue à tenir pour un texte que personne ne
/// lit, et le rang dans la palette suffit à les désigner.
String libelleTeinte(String teinte) {
  switch (teinte) {
    case "amber":
      return "Ambre";
    case "blue":
      return "Bleu";
    case "violet":
      return "Violet";
    case "teal":
      return "Vert";
    case "rose":
      return "Rose";
  }
  return teinte;
}
