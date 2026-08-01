import 'package:flutter/material.dart';
import 'whatsapp_text_parser.dart';

/// Controller qui affiche le formatage en **direct** dans le champ de saisie.
///
/// - `*gras*`, `_italique_`, `~barré~`, `__souligné__`, `` `manuscrit` ``
/// - Marqueurs atténués (35%) + contenu stylé
/// - Imbrication supportée
class WhatsappFormattingController extends TextEditingController {
  WhatsappFormattingController({super.text});

  static const Map<StyleWhatsApp, TextStyle> _styles = {
    StyleWhatsApp.gras: TextStyle(fontWeight: FontWeight.bold),
    StyleWhatsApp.italique: TextStyle(fontStyle: FontStyle.italic),
    StyleWhatsApp.barre: TextStyle(decoration: TextDecoration.lineThrough),
    StyleWhatsApp.souligne: TextStyle(decoration: TextDecoration.underline),
    StyleWhatsApp.manuscrit: TextStyle(
      fontStyle: FontStyle.italic,
      fontFamily: 'serif',
      fontFamilyFallback: ['Georgia', 'serif'],
      letterSpacing: 0.4,
      fontWeight: FontWeight.w400,
    ),
  };

  // Priorité : __ avant _
  static const List<_DefEdit> _defs = [
    _DefEdit('__', StyleWhatsApp.souligne),
    _DefEdit('*', StyleWhatsApp.gras),
    _DefEdit('_', StyleWhatsApp.italique),
    _DefEdit('~', StyleWhatsApp.barre),
    _DefEdit('`', StyleWhatsApp.manuscrit),
  ];

  bool _estBlanc(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r';

  int _chercheFermetureMulti(String s, String code, int ouverture, int fin) {
    final n = code.length;
    if (ouverture + n >= fin) return -1;
    if (_estBlanc(s[ouverture + n])) return -1;
    for (var j = ouverture + n + 1; j <= fin - n; j++) {
      if (s.startsWith(code, j) && !_estBlanc(s[j - 1])) {
        return j;
      }
    }
    return -1;
  }

  TextStyle _fusion(TextStyle base, StyleWhatsApp style) {
    final extra = _styles[style];
    if (extra == null) return base;
    return base.merge(extra);
  }

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
      bool matched = false;
      for (final def in _defs) {
        final code = def.code;
        if (i + code.length <= fin && s.startsWith(code, i)) {
          final fermeture = _chercheFermetureMulti(s, code, i, fin);
          if (fermeture != -1) {
            flush();
            spans.add(TextSpan(text: code, style: faint));
            final nouveauCourant = _fusion(courant, def.style);
            final interieurs =
                _build(s, i + code.length, fermeture, nouveauCourant, faint);
            spans.addAll(interieurs);
            spans.add(TextSpan(text: code, style: faint));
            i = fermeture + code.length;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;

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

    final faint = base.copyWith(
      color: (base.color ?? Colors.black87).withOpacity(0.35),
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );

    var children = _build(text, 0, text.length, base, faint);

    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      final compStart = value.composing.start;
      final compEnd = value.composing.end;
      if (compStart >= 0 && compEnd <= text.length && compStart < compEnd) {
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

class _DefEdit {
  const _DefEdit(this.code, this.style);
  final String code;
  final StyleWhatsApp style;
}
