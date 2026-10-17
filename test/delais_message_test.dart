import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/core/delais_message.dart';

/// Les délais pour revenir sur un message (décision du user, 07/10/2026) :
/// modifier pendant 2 heures, supprimer pour tous pendant 24 heures. Mêmes
/// valeurs que le web et que le serveur, qui tranche.
///
/// Lancer avec : flutter test test/delais_message_test.dart
void main() {
  final envoi = DateTime(2026, 10, 7, 10);
  DateTime apres(Duration d) => envoi.add(d);

  test("modifier : oui jusqu'à 2 h, non au-delà", () {
    expect(peutEncoreModifier(envoi, maintenant: apres(const Duration(minutes: 119))), isTrue);
    expect(peutEncoreModifier(envoi, maintenant: apres(const Duration(hours: 2))), isTrue);
    expect(peutEncoreModifier(envoi, maintenant: apres(const Duration(hours: 2, minutes: 1))), isFalse);
  });

  test("supprimer pour tous : oui jusqu'à 24 h, non au-delà", () {
    expect(peutEncoreSupprimerPourTous(envoi, maintenant: apres(const Duration(hours: 3))), isTrue,
        reason: "le délai de 2 h ne vaut que pour modifier");
    expect(peutEncoreSupprimerPourTous(envoi, maintenant: apres(const Duration(hours: 24))), isTrue);
    expect(peutEncoreSupprimerPourTous(envoi, maintenant: apres(const Duration(hours: 24, minutes: 1))), isFalse);
  });

  test("horloge du téléphone en retard : rien n'est refusé à tort", () {
    expect(peutEncoreModifier(envoi, maintenant: envoi.subtract(const Duration(minutes: 5))), isTrue);
  });

  test("les codes du serveur", () {
    expect(delaiModificationDepasse, 'DELAI_MODIFICATION_DEPASSE');
    expect(delaiSuppressionDepasse, 'DELAI_SUPPRESSION_DEPASSE');
  });
}
