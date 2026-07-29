import 'package:flutter/material.dart';

import 'whatsapp_format_logic.dart';

/// Application des marqueurs de mise en forme WhatsApp sur un champ de saisie.
///
/// Complément de `whatsapp_text.dart`, qui s'occupe du RENDU. Ici on écrit dans
/// le texte, côté composeur. Les deux chemins de WhatsApp aboutissent à
/// [appliqueMarqueur] : le menu contextuel sur sélection, et la barre de mise
/// en forme dépliée par le bouton « A ».
///
/// Le calcul lui-même vit dans `whatsapp_format_logic.dart`, en Dart pur, pour
/// rester testable hors Flutter.

/// Les quatre marqueurs de WhatsApp.
///
/// Pas de souligné : WhatsApp n'a pas de marqueur pour ça, et en inventer un
/// produirait un message que les autres clients afficheraient avec son
/// balisage apparent.
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
  static const chasseFixe = MarqueurWhatsApp('```', 'format_mono', Icons.code);

  static const tous = [gras, italique, barre, chasseFixe];
}

/// Applique — ou retire — le marqueur [code] autour de la sélection de [ctrl].
void appliqueMarqueur(TextEditingController ctrl, String code) {
  final sel = ctrl.selection;
  final texte = ctrl.text;
  // Une sélection invalide arrive quand le champ n'a jamais eu le focus :
  // écrire à la fin vaut mieux que ne rien faire.
  final debut = sel.isValid ? sel.start : texte.length;
  final fin = sel.isValid ? sel.end : texte.length;

  final r = calculeMarqueur(texte, debut, fin, code);

  ctrl.value = TextEditingValue(
    text: r.texte,
    selection: TextSelection(baseOffset: r.debut, extentOffset: r.fin),
    // Vider la composition : sur Android, laisser une plage héritée du clavier
    // après réécriture du texte provoque des doublons de caractères.
    composing: TextRange.empty,
  );
}
