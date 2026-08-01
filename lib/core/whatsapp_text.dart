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

/// Manuscrit : style cursif/handwritten. On utilise une famille serif en
/// italique léger pour simuler l'écriture manuscrite sans ajouter de police
/// custom (Caveat/DancingScript nécessiteraient un asset). Reste distinct de
/// l'italique simple par letterSpacing + poids léger.

const Map<StyleWhatsApp, TextStyle> _styles = {
  StyleWhatsApp.gras: TextStyle(fontWeight: FontWeight.bold),
  StyleWhatsApp.italique: TextStyle(fontStyle: FontStyle.italic),
  StyleWhatsApp.barre: TextStyle(decoration: TextDecoration.lineThrough),
  StyleWhatsApp.souligne: TextStyle(decoration: TextDecoration.underline),
  StyleWhatsApp.manuscrit: TextStyle(
    fontStyle: FontStyle.italic,
    fontFamily: 'serif',
    fontFamilyFallback: ['Georgia', 'Times New Roman', 'serif'],
    letterSpacing: 0.4,
    fontWeight: FontWeight.w400,
  ),
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
