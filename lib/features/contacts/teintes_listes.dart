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
const List<String> paletteListes = ["amber", "blue", "violet", "teal", "rose"];

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
