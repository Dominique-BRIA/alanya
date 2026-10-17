// LA BARRE DE L'ÉCRAN DE RESTAURATION — `restauration_progression.dart`.

import 'package:alanya/features/auth/restauration_progression.dart';
import 'package:alanya/services/e2ee/e2ee_sauvegarde.dart';
import 'package:flutter_test/flutter_test.dart';

ProgressionRestauration _p(EtapeRestauration e, int fait, [int? total]) =>
    ProgressionRestauration(e, fait, total);

void main() {
  test('l’ouverture n’a pas d’avancement : barre animée', () {
    expect(fractionGlobale(_p(EtapeRestauration.ouverture, 0)), isNull);
  });

  test(
    'sans total connu (serveur ancien) : barre animée, pas de chiffre inventé',
    () {
      expect(
        fractionGlobale(_p(EtapeRestauration.telechargement, 2000)),
        isNull,
      );
      expect(compteur(_p(EtapeRestauration.telechargement, 2000)), isNull);
    },
  );

  test('la barre ne recule jamais d’une étape à la suivante', () {
    final fin = fractionGlobale(
      _p(EtapeRestauration.telechargement, 100, 100),
    )!;
    final debut = fractionGlobale(_p(EtapeRestauration.dechiffrement, 0, 100))!;
    expect(debut, greaterThanOrEqualTo(fin));
    final finD = fractionGlobale(
      _p(EtapeRestauration.dechiffrement, 100, 100),
    )!;
    final debutR = fractionGlobale(_p(EtapeRestauration.rangement, 0, 50))!;
    expect(debutR, greaterThanOrEqualTo(finD));
  });

  test('le rangement terminé remplit la barre', () {
    expect(fractionGlobale(_p(EtapeRestauration.rangement, 50, 50)), 1.0);
  });

  test('une archive vide ne divise pas par zéro', () {
    expect(fractionGlobale(_p(EtapeRestauration.rangement, 0, 0)), 1.0);
  });

  test('le compteur sépare les milliers', () {
    expect(
      compteur(_p(EtapeRestauration.dechiffrement, 1250, 2100)),
      '1 250 / 2 100 blocs',
    );
    expect(compteur(_p(EtapeRestauration.rangement, 7, 42)), '7 / 42 messages');
  });
}
