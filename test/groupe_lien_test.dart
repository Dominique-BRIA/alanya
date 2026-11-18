import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/lien_alanya.dart';
import 'package:alanya/models/groupe_lien.dart';
import 'package:alanya/models/groupe_reglages.dart';

/// GROUPES PRIVÉS ET PUBLICS, LIEN ET QR CODE D'UN GROUPE (18/11/2026).
void main() {
  group('Le lien /g/<code>', () {
    const code = 'AbCdEfGhIjKlMnOpQrStUv';

    test('fabriqué puis relu : la même cible', () {
      expect(lienGroupe(code), 'https://alanyavox.com/g/$code');
      expect(analyserLienAlanya(lienGroupe(code)), const CibleGroupe(code));
    });

    test('www, http et barre finale sont acceptés', () {
      expect(analyserLienAlanya('https://www.alanyavox.com/g/$code'), const CibleGroupe(code));
      expect(analyserLienAlanya('http://alanyavox.com/g/$code/'), const CibleGroupe(code));
    });

    test('un code trop court, un autre domaine, un chemin en trop : rien', () {
      expect(analyserLienAlanya('https://alanyavox.com/g/court'), isNull);
      expect(analyserLienAlanya('https://exemple.com/g/$code'), isNull);
      expect(analyserLienAlanya('https://alanyavox.com/g/$code/plus'), isNull);
      expect(analyserLienAlanya('https://alanyavox.com/g/ab\$cdefghijklmnopq'), isNull);
    });

    test('les autres formes ne changent pas', () {
      expect(analyserLienAlanya('https://alanyavox.com/i/$code'), const CibleInvitation(code));
      expect(analyserLienAlanya('https://alanyavox.com/u/82312187'), const CibleProfil('82312187'));
    });
  });

  group('Les réglages du groupe', () {
    test('un serveur d\'avant (sans « acces ») : privé, pas de lien, 0 demande', () {
      final r = ReglagesGroupe.fromJson({'adminsSeulsAjoutent': true}, null);
      expect(r.acces, 'prive');
      expect(r.estPublic, isFalse);
      expect(r.peutPartagerLien, isFalse);
      expect(r.demandesEnAttente, 0);
    });

    test('public, lien partageable, 3 demandes ; une valeur inconnue reste privée', () {
      final r = ReglagesGroupe.fromJson(
          {'acces': 'public', 'peutPartagerLien': true, 'demandesEnAttente': 3}, null);
      expect(r.estPublic, isTrue);
      expect(r.peutPartagerLien, isTrue);
      expect(r.demandesEnAttente, 3);
      expect(ReglagesGroupe.fromJson({'acces': 'ouvert'}, null).acces, 'prive');
    });

    test('le cache relit ce qu\'il a écrit', () {
      const r = ReglagesGroupe(acces: 'public', peutPartagerLien: true, demandesEnAttente: 2);
      final j = r.toJson();
      final relu = ReglagesGroupe.fromJson(
          Map<String, dynamic>.from(j['groupe'] as Map), Map<String, dynamic>.from(j['moi'] as Map));
      expect(relu.acces, 'public');
      expect(relu.peutPartagerLien, isTrue);
      expect(relu.demandesEnAttente, 2);
    });

    test('copyWith garde le type et le droit de partager', () {
      const r = ReglagesGroupe(acces: 'public', peutPartagerLien: true);
      final c = r.copyWith(adminsSeulsEcrivent: true);
      expect(c.acces, 'public');
      expect(c.peutPartagerLien, isTrue);
      expect(r.copyWith(acces: 'prive').estPublic, isFalse);
    });
  });

  group('Les réponses du serveur', () {
    test('l\'aperçu d\'un lien', () {
      final a = ApercuGroupe.fromJson({
        'convId': 'c1',
        'nom': 'Équipe',
        'description': null,
        'avatarUrl': null,
        'membres': 12,
        'acces': 'prive',
        'chiffre': true,
        'etat': 'attente',
      });
      expect(a.nom, 'Équipe');
      expect(a.membres, 12);
      expect(a.estPublic, isFalse);
      expect(a.chiffre, isTrue);
      expect(a.enAttente, isTrue);
      expect(a.suisMembre, isFalse);
    });

    test('un état inconnu vaut « aucun »', () {
      final a = ApercuGroupe.fromJson({'convId': 'c1', 'etat': 'refusee'});
      expect(a.enAttente, isFalse);
      expect(a.suisMembre, isFalse);
      expect(a.etat, 'aucun');
    });

    test('rejoindre : membre (public) ou attente (privé)', () {
      expect(ResultatRejoindre.fromJson({'etat': 'membre', 'convId': 'c'}).membre, isTrue);
      expect(ResultatRejoindre.fromJson({'etat': 'attente', 'convId': 'c'}).membre, isFalse);
    });

    test('une demande, vue par un admin', () {
      final d = DemandeAdhesion.fromJson({
        'id': 'd1',
        'userId': 'u1',
        'pseudo': 'Awa',
        'publicNumber': '82312187',
        'avatarUrl': null,
        'creeLe': '2026-11-18T10:00:00.000Z',
      });
      expect(d.pseudo, 'Awa');
      expect(d.creeLe, isNotNull);
    });
  });
}
