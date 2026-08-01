import 'package:flutter/material.dart';
import 'whatsapp_text_parser.dart';

/// Controller WYSIWYG pour le champ de saisie Alanya Work.
///
/// Affiche `*gras*`, `_italique_`, `~barré~`, `__souligné__`, `` `manuscrit` ``
/// **en direct** dans le TextField, y compris pendant la phase de composition
/// IME (fond gris + souligné Android). Ancienne version perdait le style pendant
/// la composition car elle remplaçait le mot en cours par un span uni.
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

  static const List<_DefEdit> _defs = [
    _DefEdit('__', StyleWhatsApp.souligne), // prioritaire sur _
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

  /// Découpe un segment texte [txt] qui couvre [txtStart, txtStart+len) dans
  /// le document original en 1 à 3 spans selon qu'il chevauche la zone de
  /// composition [compStart, compEnd). Le style de la partie en composition
  /// reçoit en plus [compStyle] (underline + fond gris).
  List<InlineSpan> _spansWithComposing(
    String txt,
    int txtStart,
    TextStyle style,
    int? compStart,
    int? compEnd,
    TextStyle? compStyle,
  ) {
    if (txt.isEmpty) return const [];
    if (compStart == null ||
        compEnd == null ||
        compStyle == null ||
        txtStart >= compEnd ||
        txtStart + txt.length <= compStart) {
      return [TextSpan(text: txt, style: style)];
    }

    final res = <InlineSpan>[];
    final txtEnd = txtStart + txt.length;

    // avant composition
    if (txtStart < compStart) {
      final beforeLen = (compStart - txtStart).clamp(0, txt.length);
      if (beforeLen > 0) {
        res.add(TextSpan(
            text: txt.substring(0, beforeLen), style: style));
      }
    }

    // chevauchement
    final overlapStart = txtStart < compStart ? compStart : txtStart;
    final overlapEnd = txtEnd > compEnd ? compEnd : txtEnd;
    if (overlapStart < overlapEnd) {
      final off = overlapStart - txtStart;
      final len = overlapEnd - overlapStart;
      res.add(TextSpan(
        text: txt.substring(off, off + len),
        style: style.merge(compStyle),
      ));
    }

    // après composition
    if (txtEnd > compEnd) {
      final afterOff = compEnd - txtStart;
      if (afterOff < txt.length && afterOff >= 0) {
        res.add(TextSpan(
            text: txt.substring(afterOff), style: style));
      }
    }

    return res;
  }

  List<InlineSpan> _buildWithComposing(
    String s,
    int debut,
    int fin,
    TextStyle courant,
    TextStyle faint,
    int? compStart,
    int? compEnd,
    TextStyle? compStyle,
  ) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    int bufferStart = debut;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      final txt = buffer.toString();
      spans.addAll(_spansWithComposing(
          txt, bufferStart, courant, compStart, compEnd, compStyle));
      buffer.clear();
    }

    var i = debut;
    while (i < fin) {
      bool matched = false;
      for (final def in _defs) {
        final code = def.code;
        if (i + code.length <= fin && s.startsWith(code, i)) {
          final fermeture = _chercheFermetureMulti(s, code, i, fin);
          if (fermeture != -1) {
            flushBuffer();

            // ouvrant atténué
            spans.addAll(_spansWithComposing(
                code, i, faint, compStart, compEnd, compStyle));

            // intérieur récursif
            final newCourant = _fusion(courant, def.style);
            spans.addAll(_buildWithComposing(
              s,
              i + code.length,
              fermeture,
              newCourant,
              faint,
              compStart,
              compEnd,
              compStyle,
            ));

            // fermant atténué
            spans.addAll(_spansWithComposing(code, fermeture, faint,
                compStart, compEnd, compStyle));

            i = fermeture + code.length;
            bufferStart = i;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;

      if (buffer.isEmpty) bufferStart = i;
      buffer.write(s[i]);
      i++;
    }

    flushBuffer();
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

    int? compStart;
    int? compEnd;
    TextStyle? compStyle;

    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      compStart = value.composing.start;
      compEnd = value.composing.end;
      // On garde le fond très léger + souligné pour signaler la composition
      // mais on le fusionne avec le style formaté existant (gras, etc.)
      compStyle = TextStyle(
        backgroundColor:
            (base.color ?? Colors.black).withOpacity(0.08),
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: base.color?.withOpacity(0.4),
      );
      // bornes défensives
      if (compStart < 0) compStart = 0;
      if (compEnd > text.length) compEnd = text.length;
      if (compStart >= compEnd) {
        compStart = null;
        compEnd = null;
        compStyle = null;
      }
    }

    final children = _buildWithComposing(
      text,
      0,
      text.length,
      base,
      faint,
      compStart,
      compEnd,
      compStyle,
    );

    return TextSpan(style: base, children: children);
  }
}

class _DefEdit {
  const _DefEdit(this.code, this.style);
  final String code;
  final StyleWhatsApp style;
}
