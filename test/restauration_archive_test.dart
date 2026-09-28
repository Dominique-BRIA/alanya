import 'package:alanya/core/restauration_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('la restauration de l’archive', () {
    test('crée une ligne absente', () {
      expect(
        gesteRestauration(efface: false, ligne: null),
        GesteRestauration.inserer,
      );
    });

    test('ne recrée PAS une ligne effacée de cet appareil', () {
      expect(
        gesteRestauration(efface: true, ligne: null),
        GesteRestauration.rien,
        reason: '« supprimer pour moi » ou un éphémère expiré ressortait',
      );
    });

    test('ne touche pas une ligne supprimée pour tous', () {
      expect(
        gesteRestauration(efface: false, ligne: (texte: null, supprime: true)),
        GesteRestauration.rien,
        reason: 'le message supprimé ressortait en clair',
      );
    });

    test('ne réécrit pas un texte déjà connu', () {
      expect(
        gesteRestauration(
          efface: false,
          ligne: (texte: 'bonjour', supprime: false),
        ),
        GesteRestauration.rien,
      );
    });

    test('complète le texte d’une ligne venue du serveur sans texte', () {
      expect(
        gesteRestauration(efface: false, ligne: (texte: null, supprime: false)),
        GesteRestauration.completerTexte,
      );
      expect(
        gesteRestauration(efface: false, ligne: (texte: '', supprime: false)),
        GesteRestauration.completerTexte,
      );
    });
  });
}
