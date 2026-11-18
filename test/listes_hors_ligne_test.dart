import 'dart:convert';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/sonneries_listes.dart';
import 'package:alanya/core/token_storage.dart';
import 'package:alanya/features/contacts/contact_lists_repository.dart';
import 'package:alanya/models/contact_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LES LISTES DE CONTACTS RESTENT VISIBLES SANS CONNEXION (18/11/2026).
///
/// 🐛 Elles ne vivaient qu'en mémoire, rechargées au serveur : hors ligne, la
/// rangée de l'écran Discussions restait vide.

/// Un dépôt dont le serveur ne répond pas, ou répond [reponse].
class _Depot implements ContactListsRepository {
  _Depot({this.reponse});
  List<ListeContacts>? reponse;

  @override
  Future<List<ListeContacts>> list() async {
    final r = reponse;
    if (r == null) throw Exception('hors ligne');
    return r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _liste(String id, String nom, {List<String> membres = const []}) => {
      'id': id,
      'name': nom,
      'ringtone': null,
      'ringtoneMessage': null,
      'ordre': null,
      'color': '#B5502F',
      'cle': null,
      'createdAt': '2026-11-01T10:00:00Z',
      'members': [
        for (final m in membres) {'id': m, 'publicNumber': '12345678', 'name': m, 'isContact': true},
      ],
    };

void main() {
  test('la copie gardée sur l’appareil se relit, membres compris', () async {
    SharedPreferences.setMockInitialValues({
      'listes_contacts_cache': jsonEncode([
        _liste('l1', 'Famille', membres: ['maman', 'papa']),
        _liste('l2', 'Bureau'),
      ]),
    });
    final copie = await ContactListsRepository.enCache();
    expect(copie.map((l) => l.name), ['Famille', 'Bureau']);
    expect(copie.first.members.map((m) => m.id), ['maman', 'papa']);
  });

  test('sans copie, ou copie illisible : vide, sans lever', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ContactListsRepository.enCache(), isEmpty);
    SharedPreferences.setMockInitialValues({'listes_contacts_cache': '{pas du json'});
    expect(await ContactListsRepository.enCache(), isEmpty);
  });

  test('la déconnexion efface la copie', () async {
    SharedPreferences.setMockInitialValues({
      'listes_contacts_cache': jsonEncode([_liste('l1', 'Famille')]),
    });
    await ContactListsRepository.oublierCache();
    expect(await ContactListsRepository.enCache(), isEmpty);
  });

  test('serveur injoignable : le service affiche la copie de l’appareil', () async {
    SharedPreferences.setMockInitialValues({
      'listes_contacts_cache': jsonEncode([_liste('l1', 'Famille', membres: ['maman'])]),
    });
    final service = SonneriesDeListes(_Depot(), ApiClient(), TokenStorage());
    expect(await service.rafraichir(), isFalse);
    expect(service.listes.map((l) => l.name), ['Famille']);
  });

  test('une liste déjà affichée n’est pas remplacée par une copie plus ancienne', () async {
    SharedPreferences.setMockInitialValues({
      'listes_contacts_cache': jsonEncode([_liste('vieille', 'Ancienne')]),
    });
    final depot = _Depot(reponse: [ListeContacts.fromJson(_liste('neuve', 'Récente'))]);
    final service = SonneriesDeListes(depot, ApiClient(), TokenStorage());
    await service.rafraichir();
    depot.reponse = null; // le réseau tombe
    await service.rafraichir();
    expect(service.listes.map((l) => l.name), ['Récente']);
  });
}
