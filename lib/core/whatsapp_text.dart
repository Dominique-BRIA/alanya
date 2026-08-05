import 'package:flutter/material.dart';

import 'whatsapp_text_parser.dart';

export 'whatsapp_text_parser.dart' show sansMarqueursWhatsApp;

/// Rendu Flutter de la mise en forme Alanya Work.
///
/// Toute l'analyse vit dans `whatsapp_text_parser.dart`, en Dart pur pour
/// rester testable hors Flutter. Ce fichier ne fait que traduire l'arbre
/// obtenu en `InlineSpan`.
///
/// Marqueurs :
/// *gras*, _italique_, ~barré~, __souligné__, `manuscrit`
///
/// Le contenu **stocké et envoyé reste le texte brut**, marqueurs compris.

/// Manuscrit : vraie écriture cursive, la police Caveat étant embarquée avec
/// l'application (voir `pubspec.yaml`).
///
/// Ce style était auparavant SIMULÉ — du serif en italique, avec Georgia et
/// Times New Roman en replis. Aucune de ces deux polices n'existant sur
/// Android, le rendu réel était du Noto Serif penché : visiblement pas de
/// l'écriture manuscrite.
///
/// Ni `fontStyle`, ni `letterSpacing`, ni `fontWeight` ne sont repris : ils ne
/// servaient qu'à éloigner la simulation de l'italique simple. Pencher une
/// cursive la déforme, et l'espacer rompt la liaison entre ses lettres — c'est
/// précisément ce qui fait qu'on la lit comme une écriture.
const Map<StyleWhatsApp, TextStyle> _styles = {
  StyleWhatsApp.gras: TextStyle(fontWeight: FontWeight.bold),
  StyleWhatsApp.italique: TextStyle(fontStyle: FontStyle.italic),
  StyleWhatsApp.barre: TextStyle(decoration: TextDecoration.lineThrough),
  StyleWhatsApp.souligne: TextStyle(decoration: TextDecoration.underline),
  StyleWhatsApp.manuscrit: TextStyle(fontFamily: 'Caveat'),
};

List<InlineSpan> _versSpans(List<NoeudTexte> noeuds) {
  return noeuds.map<InlineSpan>((n) {
    if (n.texte != null) return TextSpan(text: n.texte);
    return TextSpan(style: _styles[n.style], children: _versSpans(n.enfants));
  }).toList();
}

/// Transforme [source] en `InlineSpan` prêts pour un `Text.rich`.
List<InlineSpan> spansWhatsApp(String source) =>
    _versSpans(analyseWhatsApp(source));
