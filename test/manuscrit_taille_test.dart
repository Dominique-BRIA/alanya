// LE MANUSCRIT EST AGRANDI (02/10/2026) : Caveat a un très petit œil, le
// user le trouvait illisible à la taille du texte voisin.

import 'package:alanya/core/whatsapp_text.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

TextSpan _manuscrit(List<InlineSpan> spans) => spans
    .whereType<TextSpan>()
    .firstWhere((s) => s.style?.fontFamily == 'Caveat');

void main() {
  test('dans une bulle (14) : 1,45 fois, soit 20,3', () {
    final m = _manuscrit(spansWhatsApp('salut `toi`'));
    expect(m.style!.fontSize, closeTo(20.3, 0.01));
  });

  test('dans l’aperçu de la liste (12) : proportionnel à SA taille', () {
    final m = _manuscrit(spansWhatsApp('`toi`', tailleBase: 12));
    expect(m.style!.fontSize, closeTo(17.4, 0.01));
  });

  test('les autres styles ne changent pas de taille', () {
    final gras = spansWhatsApp('*gras*').whereType<TextSpan>().first;
    expect(gras.style!.fontSize, isNull);
  });
}
