import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/models/status.dart';

/// La copie des statuts gardée sur le téléphone écarte ce que le temps a
/// expiré. Lancer avec : flutter test test/statuts_copie_locale_test.dart
void main() {
  final maintenant = DateTime.utc(2026, 10, 18, 12);
  String iso(Duration d) => maintenant.add(d).toIso8601String();

  Map<String, dynamic> statut(String id, Duration expire) => {
        'id': id,
        'type': 'TEXT',
        'text': id,
        'bgColor': '#000000',
        'createdAt': iso(-const Duration(hours: 1)),
        'expiresAt': iso(expire),
        'viewed': false,
      };

  Map<String, dynamic> groupe(String userId, List<Map<String, dynamic>> s) => {
        'userId': userId,
        'pseudo': userId,
        'avatarUrl': null,
        'publicNumber': '67641599',
        'hasUnviewed': true,
        'statuses': s,
      };

  test('les statuts expirés disparaissent, les autres restent', () {
    final feed = StatusFeed.fromJson({
      'me': groupe('moi', [
        statut('m1', const Duration(hours: 2)),
        statut('m2', -const Duration(minutes: 1)),
      ]),
      'others': [
        groupe('awa', [statut('a1', const Duration(hours: 5))]),
      ],
    }).sansExpires(maintenant);

    expect(feed.me!.statuses.map((s) => s.id), ['m1']);
    expect(feed.others.single.statuses.map((s) => s.id), ['a1']);
  });

  test('une personne sans statut restant sort de la liste', () {
    final feed = StatusFeed.fromJson({
      'me': groupe('moi', [statut('m1', -const Duration(hours: 1))]),
      'others': [
        groupe('awa', [statut('a1', -const Duration(seconds: 1))]),
        groupe('paul', [statut('p1', const Duration(hours: 1))]),
      ],
    }).sansExpires(maintenant);

    expect(feed.me, isNull);
    expect(feed.others.map((g) => g.userId), ['paul']);
  });
}
