import 'package:flutter/material.dart';

import 'whatsapp_format_logic.dart';

/// Application des marqueurs de mise en forme Alanya Work sur un champ de saisie.
///
/// Barre de mise en forme dépliée par le bouton « A » + menu contextuel natif.
/// Le calcul vit dans `whatsapp_format_logic.dart` en Dart pur pour rester testable.

/// Les cinq marqueurs Alanya Work.
/// - `*gras*`, `_italique_`, `~barré~`, `__souligné__`, `` `manuscrit` ``
/// L'ancien chasse fixe ```...``` (icône <>) a été retiré sur demande.
class MarqueurWhatsApp {
  const MarqueurWhatsApp(this.code, this.cleTraduction, this.icone);

  final String code;
  final String cleTraduction;
  final IconData icone;

  static const gras = MarqueurWhatsApp('*', 'format_bold', Icons.format_bold);
  static const italique =
      MarqueurWhatsApp('_', 'format_italic', Icons.format_italic);
  static const barre =
      MarqueurWhatsApp('~', 'format_strike', Icons.format_strikethrough);
  static const souligne =
      MarqueurWhatsApp('__', 'format_underline', Icons.format_underline);
  // Icône manuscrit : brush = pinceau, plus évocateur que draw (qui peut manquer sur vieilles versions)
  static const manuscrit =
      MarqueurWhatsApp('`', 'format_handwritten', Icons.brush);

  static const tous = [gras, italique, barre, souligne, manuscrit];
}

/// Applique — ou retire — le marqueur [code] autour de la sélection de [ctrl].
void appliqueMarqueur(TextEditingController ctrl, String code) {
  final sel = ctrl.selection;
  final texte = ctrl.text;
  final debut = sel.isValid ? sel.start : texte.length;
  final fin = sel.isValid ? sel.end : texte.length;

  final r = calculeMarqueur(texte, debut, fin, code);

  ctrl.value = TextEditingValue(
    text: r.texte,
    selection: TextSelection(baseOffset: r.debut, extentOffset: r.fin),
    composing: TextRange.empty,
  );
}
