import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/features/chat/envoi_morceaux/decoupage_morceaux.dart';
import 'package:alanya/features/chat/envoi_morceaux/envoi_morceaux_api.dart';
import 'package:alanya/features/chat/envoi_morceaux/transport_morceaux.dart';

/// L'ENVOI EN MORCEAUX, côté téléphone : découpage, pourcentage, identifiants
/// de tâche, lecture des réponses du serveur (cours, chapitre 44).
///
/// Lancer avec : flutter test test/envoi_morceaux_test.dart
void main() {
  const mio = 1024 * 1024;

  group('Le découpage, jumeau de src/lib/envoi-morceaux.mjs', () {
    test('2,5 Mio + 37 : trois morceaux, le dernier court', () {
      final m = morceauxDe(2 * mio + mio ~/ 2 + 37, mio);
      expect(m.length, 3);
      expect(m.map((x) => x.taille), [mio, mio, mio ~/ 2 + 37]);
      expect(m.last.debut, 2 * mio);
    });

    test('pile un mébioctet : UN morceau', () {
      expect(morceauxDe(mio, mio).length, 1);
    });

    test("l'en-tête Range a une borne de fin INCLUSE", () {
      final m = morceauxDe(2 * mio + 10, mio);
      expect(m[0].plage, 'bytes=0-${mio - 1}');
      expect(m[2].plage, 'bytes=${2 * mio}-${2 * mio + 9}');
    });

    test('les morceaux couvrent tout le fichier, sans trou ni chevauchement', () {
      final m = morceauxDe(7 * mio + 12345, mio);
      for (var i = 1; i < m.length; i++) {
        expect(m[i].debut, m[i - 1].fin);
      }
      expect(m.first.debut, 0);
      expect(m.last.fin, 7 * mio + 12345);
    });

    test('une taille nulle est refusée (un chiffré AGB1 ne l\'est jamais)', () {
      expect(() => morceauxDe(0, mio), throwsArgumentError);
    });
  });

  group('Le pourcentage affiché', () {
    test('pondéré par les octets : le petit dernier morceau compte peu', () {
      final p = ProgressionEnvoi(morceauxDe(2 * mio + mio ~/ 10, mio));
      p.morceauRecu(2); // le dernier, petit
      expect(p.pourcent, lessThan(10));
      p.morceauRecu(0);
      // (1 Mio + 0,1 Mio) / 2,1 Mio = 52,4 %.
      expect(p.pourcent, 52);
    });

    test('suit les morceaux en vol : 10, 15, 18, 20 %…', () {
      final p = ProgressionEnvoi(morceauxDe(10 * mio, mio));
      p.avancer(0, 1);
      expect(p.pourcent, 10);
      p.avancer(1, 0.5);
      expect(p.pourcent, 15);
      p.avancer(2, 0.3);
      expect(p.pourcent, 18);
      p.avancer(1, 1);
      p.avancer(2, 0);
      // Un réessai repart de zéro : la barre, elle, ne recule pas.
      expect(p.pourcent, 23);
    });

    test('JAMAIS 100 % avant la réponse du serveur', () {
      final p = ProgressionEnvoi(morceauxDe(3 * mio, mio));
      for (var i = 0; i < 3; i++) {
        p.morceauRecu(i);
      }
      expect(p.pourcent, 99);
      p.terminer();
      expect(p.pourcent, 100);
    });

    test('reprise : les morceaux que le serveur a déjà comptent', () {
      final p = ProgressionEnvoi(morceauxDe(4 * mio, mio));
      p.dejaRecus([0, 1]);
      expect(p.pourcent, 50);
    });

    test('une progression invalide (code négatif, NaN) est ignorée', () {
      final p = ProgressionEnvoi(morceauxDe(2 * mio, mio));
      p.avancer(0, double.nan);
      p.avancer(7, 1);
      expect(p.pourcent, 0);
    });
  });

  group("Les identifiants de tâche survivent à l'application", () {
    test('aller-retour', () {
      final id = idTacheMorceau('4c86695e-0000-4000-8000-000000000000', 12);
      expect(lireIdTacheMorceau(id),
          (envoiId: '4c86695e-0000-4000-8000-000000000000', indice: 12));
    });

    test("une tâche d'autre chose est ignorée", () {
      expect(lireIdTacheMorceau('telechargement-42'), isNull);
      expect(lireIdTacheMorceau('morceau|x|pas-un-nombre'), isNull);
    });
  });

  group('Les réponses du serveur', () {
    test('un morceau intermédiaire : pas terminé', () {
      final e = EtatEnvoiServeur.depuisJson({'recus': 1, 'total': 3, 'termine': false});
      expect(e.termine, isFalse);
      expect(e.publication, isNull);
    });

    test('le dernier morceau : terminé, publié, avec son message', () {
      final e = EtatEnvoiServeur.depuisJson({
        'statut': 'termine',
        'termine': true,
        'manquants': [],
        'publication': {'etat': 'publie', 'messageId': 'm1'},
      });
      expect(e.termine && e.publie, isTrue);
      expect(e.messageId, 'm1');
    });

    test('un refus à la publication se reconnaît', () {
      final e = EtatEnvoiServeur.depuisJson({
        'statut': 'termine',
        'publication': {'etat': 'refus:VERSION_PERIMEE', 'messageId': null},
      });
      expect(e.termine, isTrue);
      expect(e.refuse, isTrue);
      expect(e.publie, isFalse);
    });

    test('la réservation rend le média sous l\'identifiant de l\'envoi', () {
      final r = ReservationEnvoi.depuisJson(
          {'id': 'e1', 'jeton': 'j', 'tailleMorceau': mio, 'nbMorceaux': 3});
      expect(r.mediaId, 'e1');
      expect(ReservationEnvoi.depuisJson(r.toJson()).jeton, 'j');
    });
  });
}
