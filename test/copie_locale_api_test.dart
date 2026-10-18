import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/cache_ecrans.dart';
import 'package:alanya/models/badge_compte.dart';
import 'package:alanya/models/conversation.dart';

/// Lecture des copies locales sans réseau, et badge du compte officiel.
/// Lancer avec : flutter test test/copie_locale_api_test.dart
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiClient.copieSeulement', () {
    // Une adresse injoignable : si un appel réseau partait, le test échouerait.
    final api = ApiClient(baseUrl: 'http://127.0.0.1:9');

    test('un chemin gardé rend sa copie, sans réseau', () async {
      await CacheEcrans.ecrire('api/api/blocked', {
        'blocked': [
          {'id': 'u1'}
        ]
      });
      final r = await ApiClient.copieSeulement(() => api.get('/api/blocked'));
      expect(r['blocked'], hasLength(1));
    });

    test('la requête fait partie de la clé', () async {
      await CacheEcrans.ecrire('api/api/user-access?limit=20', {'acces': []});
      final r = await ApiClient.copieSeulement(
          () => api.get('/api/user-access?limit=20'));
      expect(r['acces'], isEmpty);
      expect(
        ApiClient.copieSeulement(() => api.get('/api/user-access?limit=50')),
        throwsA(isA<ApiException>()),
      );
    });

    test('pas de copie : échec, jamais le réseau', () {
      expect(ApiClient.copieSeulement(() => api.get('/api/blocked')),
          throwsA(isA<ApiException>()));
    });

    test('un chemin non gardé (messages…) ne se lit jamais en copie', () async {
      await CacheEcrans.ecrire('api/api/conversations', {'conversations': []});
      expect(ApiClient.copieSeulement(() => api.get('/api/conversations')),
          throwsA(isA<ApiException>()));
    });

    test('aucune écriture en lecture de copie', () {
      expect(ApiClient.copieSeulement(() => api.post('/api/blocked', {})),
          throwsA(isA<ApiException>()));
      expect(ApiClient.copieSeulement(() => api.delete('/api/blocked')),
          throwsA(isA<ApiException>()));
    });

    test('hors de copieSeulement, le mode copie est éteint', () {
      expect(ApiClient.enCopieSeule, isFalse);
    });
  });

  group('Conversation.badgeAffiche', () {
    Conversation conv({bool officiel = false, bool groupe = false, BadgeCompte? badge}) =>
        Conversation(
          id: 'c1',
          isGroup: groupe,
          title: 'Alanya Work',
          avatarUrl: null,
          members: const [],
          lastMessage: null,
          unread: 0,
          updatedAt: DateTime(2026, 10, 18),
          officiel: officiel,
          badge: badge,
        );

    test('le badge du serveur prime', () {
      const verifie = BadgeCompte(type: 'verifie', image: 'https://x/v.png', libelle: 'V');
      expect(conv(officiel: true, badge: verifie).badgeAffiche, same(verifie));
    });

    test('fil officiel sans badge du serveur : le badge officiel reste', () {
      final b = conv(officiel: true).badgeAffiche;
      expect(b?.type, 'officiel');
      expect(b?.imageEmbarquee, 'assets/images/badges/officiel.png');
    });

    test('fil ordinaire sans badge : rien', () {
      expect(conv().badgeAffiche, isNull);
      expect(conv(officiel: true, groupe: true).badgeAffiche, isNull);
    });

    test('un type inconnu de l\'application n\'a pas d\'image embarquée', () {
      expect(const BadgeCompte(type: 'autre', image: 'x', libelle: '').imageEmbarquee, isNull);
    });
  });
}
