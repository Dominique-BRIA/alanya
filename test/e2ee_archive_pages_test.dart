// L'ARCHIVE SE RELIT JUSQU'AU BOUT, page après page.
//
// 🐛 On ne lisait que la première page (2 000 blocs) : au-delà, les messages
// les plus RÉCENTS manquaient à la restauration. Le serveur pagine depuis le
// lot 5 (`?apres=` / `suivant`), prouvé par `e2ee-archive-banc.mjs` ⑧.

import 'package:alanya/services/e2ee/e2ee_sauvegarde.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2 100 blocs, deux pages : tous relus, dans l’ordre', () async {
    final blocs = [
      for (var i = 0; i < 2100; i++) {'iv': 'aXY=', 'contenu': 'b$i'},
    ];
    final chemins = <String>[];
    final s = E2eeSauvegarde((methode, chemin, corps) async {
      chemins.add(chemin);
      final apres = Uri.parse(chemin).queryParameters['apres'];
      final debut = apres == null ? 0 : int.parse(apres) + 1;
      final fin = (debut + 2000).clamp(0, blocs.length);
      final page = blocs.sublist(debut, fin);
      return {
        'blocs': page,
        'suivant': page.length == 2000 ? '${debut + 1999}' : null,
      };
    });

    final lus = await s.lireTousLesBlocs();

    expect(lus.length, 2100);
    expect(lus.last['contenu'], 'b2099', reason: 'le plus récent manque');
    expect(chemins, ['/api/e2ee/archive', '/api/e2ee/archive?apres=1999']);
  });

  test('un serveur antérieur, sans `suivant` : une page, comme avant', () async {
    final s = E2eeSauvegarde((m, c, corps) async => {
          'blocs': [
            {'iv': 'aXY=', 'contenu': 'seul'},
          ],
        });
    expect((await s.lireTousLesBlocs()).single['contenu'], 'seul');
  });

  // 🐛 LA REPRISE AU DÉMARRAGE COMPTAIT LA PREMIÈRE PAGE, pas l'archive. Passé
  // 2 000 blocs, ce compte restait figé à 2 000 : l'archive avait beau grossir,
  // la reprise croyait n'avoir rien de neuf et ne se relançait plus.
  test('la reprise compte TOUTE l’archive, pas la première page', () {
    final premiere = {
      'blocs': List.filled(2000, {'iv': 'aXY=', 'contenu': 'x'}),
      'suivant': 'dernier',
      'totalArchive': 2100,
    };
    expect(E2eeSauvegarde.nombreDeBlocs(premiere), 2100,
        reason: 'au-delà de 2 000 blocs, la reprise ne voyait plus l’archive grossir');
  });

  test('un serveur antérieur, sans `totalArchive` : la page fait foi', () {
    expect(
      E2eeSauvegarde.nombreDeBlocs({
        'blocs': [
          {'iv': 'aXY=', 'contenu': 'seul'},
        ],
      }),
      1,
    );
  });
}
