import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// « IDENTITÉ ABSENTE — APPELER PREPARER() » (14/11/2026, Ibrahim Traore vers
/// Doms, juste après la connexion) : un envoi qui demande l'identité avant que
/// la préparation de fond l'ait créée doit l'ATTENDRE, pas échouer — et deux
/// préparations simultanées ne doivent créer qu'UNE identité.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test("lire l'identité d'un coffre neuf la crée au lieu de lever", () async {
    final coffre = CoffreE2ee('ibrahim');
    final identite = await coffre.identiteLocale();
    expect(identite.getPublicKey().serialize(), isNotEmpty);
    expect(await coffre.getLocalRegistrationId(), greaterThan(0));
    // Relue ensuite : la même.
    expect((await coffre.identiteLocale()).getPublicKey().serialize(),
        identite.getPublicKey().serialize());
  });

  test('préparation et envoi simultanés : une seule identité, un seul avis', () async {
    final coffre = CoffreE2ee('ibrahim');
    var avis = 0;
    coffre.surIdentiteNeuve = () => avis++;
    final resultats = await Future.wait([
      coffre.preparer().then((_) => coffre.identiteLocale()),
      coffre.identiteLocale(),
      coffre.getIdentityKeyPair(),
    ]);
    final cles = resultats.map((r) => r.getPublicKey().serialize().toString()).toSet();
    expect(cles, hasLength(1));
    expect(avis, 1);
  });

  test('une identité déjà là ne déclenche aucun avis', () async {
    final coffre = CoffreE2ee('doms');
    await coffre.preparer();
    var avis = 0;
    coffre.surIdentiteNeuve = () => avis++;
    await coffre.preparer();
    await coffre.identiteLocale();
    expect(avis, 0);
  });

  test("une identité neuve n'est pas considérée comme publiée", () async {
    final coffre = CoffreE2ee('ibrahim');
    await coffre.noterPublie();
    expect(await coffre.dejaPublie(), isTrue);
    // Le coffre a perdu son identité (réparation) mais pas son drapeau : la
    // nouvelle doit repartir à la publication.
    await coffre.identiteLocale();
    expect(await coffre.dejaPublie(), isFalse);
  });

  test('les comptes ne se mélangent pas', () async {
    final a = await CoffreE2ee('ibrahim').identiteLocale();
    final b = await CoffreE2ee('doms').identiteLocale();
    expect(a.getPublicKey().serialize(), isNot(equals(b.getPublicKey().serialize())));
  });
}
