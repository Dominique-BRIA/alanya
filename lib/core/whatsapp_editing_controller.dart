import 'package:flutter/material.dart';
import 'whatsapp_text_parser.dart';

/// Controller qui affiche le formatage en **direct** dans le champ de saisie.
///
/// Comportement désiré :
/// - Quand l'utilisateur tape `*gras*`, le mot `gras` apparaît déjà en gras
///   dans le TextField, les `*` restant visibles mais atténués.
/// - Idem pour `_italique_`, `~barré~`, ` ```code``` `.
/// - Imbrication supportée : `*_gras italique_*` → gras+italique.
/// - Le texte STOCKÉ garde les marqueurs (compatibilité), seul l'affichage
///   est enrichi.
///
/// On surcharge [buildTextSpan] : c'est le hook prévu par Flutter pour
/// styler le contenu du champ sans toucher à [text].
class WhatsappFormattingController extends TextEditingController {
  WhatsappFormattingController({super.text});

  // Styles de base pour chaque marqueur — identiques à whatsapp_text.dart
  static const _styleChasseFixe = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier New', 'Courier'],
  );

  static const Map<StyleWhatsApp, TextStyle> _styles = {
    StyleWhatsApp.gras: TextStyle(fontWeight: FontWeight.bold),
    StyleWhatsApp.italique: TextStyle(fontStyle: FontStyle.italic),
    StyleWhatsApp.barre: TextStyle(decoration: TextDecoration.lineThrough),
    StyleWhatsApp.chasseFixe: _styleChasseFixe,
  };

  static const _marqueurs = {
    '*': StyleWhatsApp.gras,
    '_': StyleWhatsApp.italique,
    '~': StyleWhatsApp.barre,
  };

  static const _chasseFixe = '```';

  bool _estBlanc(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r';

  int _chercheFermeture(String s, String marqueur, int ouverture, int fin) {
    if (ouverture + 1 >= fin || _estBlanc(s[ouverture + 1])) return -1;
    for (var j = ouverture + 2; j < fin; j++) {
      if (s[j] == marqueur && !_estBlanc(s[j - 1])) return j;
    }
    return -1;
  }

  TextStyle _fusion(TextStyle base, StyleWhatsApp style) {
    final extra = _styles[style];
    if (extra == null) return base;
    return base.merge(extra);
  }

  /// Construit les InlineSpan pour la portion [debut, fin) avec le style
  /// courant [courant] et les marqueurs atténués [faint].
  List<InlineSpan> _build(
    String s,
    int debut,
    int fin,
    TextStyle courant,
    TextStyle faint,
  ) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString(), style: courant));
        buffer.clear();
      }
    }

    var i = debut;
    while (i < fin) {
      // Chasse fixe ```...``` prioritaire
      if (i + 3 <= fin && s.startsWith(_chasseFixe, i)) {
        final fermeture = s.indexOf(_chasseFixe, i + 3);
        if (fermeture != -1 &&
            fermeture + 3 <= fin &&
            fermeture > i + 3) {
          flush();
          // ouvrant
          spans.add(TextSpan(text: _chasseFixe, style: faint));
          // contenu monospaced
          final interieur = s.substring(i + 3, fermeture);
          spans.add(TextSpan(
            text: interieur,
            style: _fusion(courant, StyleWhatsApp.chasseFixe),
          ));
          // fermant
          spans.add(TextSpan(text: _chasseFixe, style: faint));
          i = fermeture + 3;
          continue;
        }
      }

      final styleMarqueur = _marqueurs[s[i]];
      if (styleMarqueur != null) {
        final fermeture = _chercheFermeture(s, s[i], i, fin);
        if (fermeture != -1) {
          flush();
          // ouvrant atténué
          spans.add(TextSpan(text: s[i], style: faint));
          // intérieur récursif avec style enrichi
          final nouveauCourant = _fusion(courant, styleMarqueur);
          final interieurs =
              _build(s, i + 1, fermeture, nouveauCourant, faint);
          spans.addAll(interieurs);
          // fermant atténué
          spans.add(TextSpan(text: s[i], style: faint));
          i = fermeture + 1;
          continue;
        }
      }

      buffer.write(s[i]);
      i++;
    }

    flush();
    return spans;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    final base = style ?? const TextStyle(fontSize: 16);
    if (text.isEmpty) {
      return TextSpan(text: '', style: base);
    }

    // Marqueurs atténués mais toujours lisibles
    final faint = base.copyWith(
      color: (base.color ?? Colors.black87).withOpacity(0.35),
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );

    var children = _build(text, 0, text.length, base, faint);

    // Gestion minimale du composing (IME asiatiques) : soulignement
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      final compStart = value.composing.start;
      final compEnd = value.composing.end;
      if (compStart >= 0 && compEnd <= text.length && compStart < compEnd) {
        // Pour rester simple on enveloppe tout et on ajoute un span souligné
        // par-dessus la zone composing en réutilisant les enfants déjà parsés
        // — on reconstruit linéairement pour ne pas perdre les styles.
        // Approche pragmatique : on repasse en texte brut pour le soulignement,
        // car le cas composing + formatage simultané est rarissime.
        final plain = text;
        final before = plain.substring(0, compStart);
        final composingText = plain.substring(compStart, compEnd);
        final after = plain.substring(compEnd);

        children = [
          if (before.isNotEmpty)
            ..._build(before, 0, before.length, base, faint),
          TextSpan(
            text: composingText,
            style: base.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.solid,
              backgroundColor: base.color?.withOpacity(0.08) ??
                  Colors.grey.withOpacity(0.15),
            ),
          ),
          if (after.isNotEmpty)
            ..._build(after, 0, after.length, base, faint),
        ];
      }
    }

    return TextSpan(style: base, children: children);
  }
}
