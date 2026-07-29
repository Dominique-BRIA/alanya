import 'package:flutter/material.dart';

import 'whatsapp_text_parser.dart';

export 'whatsapp_text_parser.dart' show sansMarqueursWhatsApp;

/// Rendu Flutter de la mise en forme WhatsApp.
///
/// Toute l'analyse vit dans `whatsapp_text_parser.dart`, en Dart pur pour
/// rester testable hors Flutter. Ce fichier ne fait que traduire l'arbre
/// obtenu en `InlineSpan`.
///
/// Le mécanisme est celui de WhatsApp : on tape les marqueurs dans le message,
/// ils disparaissent à l'affichage et laissent place au style. Le contenu
/// **stocké et envoyé reste le texte brut**, marqueurs compris — un client qui
/// ne les interprète pas affiche donc un message lisible plutôt qu'un balisage
/// perdu.

const TextStyle _styleChasseFixe = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Courier New', 'Courier'],
);

const Map<StyleWhatsApp, TextStyle> _styles = {
  StyleWhatsApp.gras: TextStyle(fontWeight: FontWeight.bold),
  StyleWhatsApp.italique: TextStyle(fontStyle: FontStyle.italic),
  StyleWhatsApp.barre: TextStyle(decoration: TextDecoration.lineThrough),
  StyleWhatsApp.chasseFixe: _styleChasseFixe,
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
