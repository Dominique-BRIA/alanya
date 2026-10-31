import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/features/status/statuts_en_direct.dart';
import 'package:alanya/models/status.dart';

/// Statut audio, « J'aime » et compteurs en direct (01/11/2026).
/// Lancer avec : flutter test test/statuts_en_direct_test.dart
void main() {
  String iso(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

  Map<String, dynamic> statut(String id, Duration expire,
          {bool vu = false, Map<String, dynamic> plus = const {}}) =>
      {
        'id': id,
        'type': 'TEXT',
        'text': id,
        'bgColor': '#000000',
        'createdAt': iso(-const Duration(hours: 1)),
        'expiresAt': iso(expire),
        'viewed': vu,
        'viewsCount': 2,
        ...plus,
      };

  StatusFeed fil(List<Map<String, dynamic>> statuts) => StatusFeed(
        me: null,
        others: [
          StatusGroup.fromJson({
            'userId': 'u1',
            'pseudo': 'Awa',
            'avatarUrl': null,
            'publicNumber': '67641599',
            'hasUnviewed': true,
            'statuses': statuts,
          }),
        ],
      );

  test('un statut audio garde sa durée, « J\'aime » et compte', () {
    final s = StatusItem.fromJson(statut('a', const Duration(hours: 1), plus: {
      'type': 'AUDIO',
      'mediaUrl': '/api/media/m1',
      'mediaDurationMs': 12500,
      'likedByMe': true,
      'likesCount': 3,
    }));
    expect(s.type, 'AUDIO');
    expect(s.mediaDurationMs, 12500);
    expect(s.likedByMe, isTrue);
    expect(s.likesCount, 3);
    // Un ancien serveur n'envoie rien : pas aimé, compte inconnu.
    final ancien = StatusItem.fromJson(statut('b', const Duration(hours: 1)));
    expect(ancien.likedByMe, isFalse);
    expect(ancien.likesCount, isNull);
  });

  test('l\'anneau ne garde que les statuts encore en ligne', () {
    final direct = StatutsEnDirect.instance;
    direct.retenirFil(fil([
      statut('vieux', const Duration(minutes: -5), vu: false),
      statut('frais', const Duration(hours: 3), vu: true),
    ]));
    final g = direct.groupeDe('u1')!;
    expect(g.statuses.map((s) => s.id), ['frais']);
    expect(g.hasUnviewed, isFalse);
    expect(direct.groupeDe('inconnu'), isNull);
    expect(direct.groupeDe(null), isNull);

    direct.retenirFil(fil([statut('vieux', const Duration(minutes: -5))]));
    expect(direct.groupeDe('u1'), isNull);
  });

  test('les compteurs reçus en direct passent devant le fil', () {
    final direct = StatutsEnDirect.instance;
    direct.retenirFil(fil([statut('s1', const Duration(hours: 3))]));
    final s = direct.groupeDe('u1')!.statuses.single;
    expect(direct.vues(s), 2);
    expect(direct.aimes(s), 0);

    var notifie = 0;
    void ecoute() => notifie++;
    direct.addListener(ecoute);
    direct.recevoir({'type': 'statut_vu', 'statusId': 's1', 'viewsCount': 5});
    direct.recevoir({'type': 'statut_aime', 'statusId': 's1', 'likesCount': 1});
    direct.recevoir({'type': 'autre', 'statusId': 's1'});
    direct.removeListener(ecoute);
    expect(notifie, 2);
    expect(direct.vues(s), 5);
    expect(direct.aimes(s), 1);

    direct.marquerAime('s1', true);
    expect(direct.aimeParMoi(s), isTrue);

    // Un fil plus récent remet les compteurs à ce qu'il dit.
    direct.retenirFil(fil([statut('s1', const Duration(hours: 3))]));
    expect(direct.vues(s), 2);
    expect(direct.aimeParMoi(s), isFalse);
  });
}
