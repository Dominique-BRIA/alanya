/// OÙ PLACER LA BANDE « À PARTIR D'ICI, CHIFFRÉ ».
///
/// Fonction PURE, éprouvée par `test/frontiere_chiffrement_test.dart`.
library;

import '../../models/message.dart';

/// L'indice (chronologique) du PREMIER message chiffré du fil, ou `null`.
///
/// 🐛 SIGNALÉ PAR LE USER LE 28/09/2026 : sur mobile, la bande s'affichait TOUT
/// EN HAUT de la conversation, au-dessus de messages qui n'étaient pas chiffrés.
/// Elle était posée comme un élément de plus en tête du fil. Or elle dit
/// « les messages envoyés À PARTIR D'ICI sont chiffrés ; les précédents restent
/// lisibles » : sa place est juste avant le premier message chiffré — celle
/// qu'elle a sur le web (`frontiereChiffrement`, `premierChiffreId`).
///
/// ⚠️ `null` QUAND AUCUN MESSAGE N'EST CHIFFRÉ — chiffrement activé, rien
/// encore envoyé : la bande ne s'affiche pas, comme sur le web. Elle n'aurait
/// aucun « ici » à désigner.
///
/// [elements] mêle messages, groupes de médias et appels ; seuls les messages
/// portent l'indicateur, les médias n'étant pas chiffrés.
int? indiceFrontiere(List<dynamic> elements) {
  for (var i = 0; i < elements.length; i++) {
    final e = elements[i];
    if (e is Message && e.chiffre) return i;
  }
  return null;
}
