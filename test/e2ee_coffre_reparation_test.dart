import 'package:alanya/services/e2ee/e2ee_coffre.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// UN COFFRE ILLISIBLE SE RÉPARE ; UNE ERREUR PASSAGÈRE N'EFFACE RIEN
/// (14/11/2026, Ibrahim Traore : « Failed to unwrap key » à chaque accès, aucun
/// envoi possible).
///
/// Le faux stockage imite la bibliothèque Android : tant que le coffre est
/// « cassé », TOUTE opération ordinaire lève l'erreur de migration — effacement
/// compris, puisque la bibliothèque ouvre le coffre avant d'agir. Seul un accès
/// avec `resetOnError: true` remet l'espace à zéro (`deleteAllDataAndKeys`).
class _StockageAndroid extends FlutterSecureStoragePlatform {
  final Map<String, String> donnees = {};

  /// Le coffre ne s'ouvre plus (clé du Keystore perdue).
  bool casse = false;

  /// Nombre d'opérations ordinaires qui échoueront encore (erreur passagère).
  int echecsPassagers = 0;

  int remisesAZero = 0;

  void _ouvrir(Map<String, String> options) {
    if (casse && options['resetOnError'] == 'true') {
      casse = false;
      donnees.clear();
      remisesAZero++;
      return;
    }
    if (casse || echecsPassagers > 0) {
      if (echecsPassagers > 0) echecsPassagers--;
      throw PlatformException(
        code: 'Exception encountered',
        message: 'Migration failed after algorithm change (Invalid key, key type '
            'incompatible with cipher). Enable resetOnError=true or call deleteAll().',
        details: 'Caused by: java.security.InvalidKeyException: Failed to unwrap key',
      );
    }
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async {
    _ouvrir(options);
    return donnees[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _ouvrir(options);
    donnees[key] = value;
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async {
    _ouvrir(options);
    return donnees.containsKey(key);
  }

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    _ouvrir(options);
    donnees.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async {
    _ouvrir(options);
    return Map.of(donnees);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _ouvrir(options);
    donnees.clear();
  }
}

void main() {
  late _StockageAndroid stockage;

  setUp(() {
    stockage = _StockageAndroid();
    FlutterSecureStoragePlatform.instance = stockage;
  });

  test('coffre illisible : remis à zéro, identité neuve, republication demandée', () async {
    final coffre = CoffreE2ee('ibrahim');
    final ancienne = (await coffre.identiteLocale()).getPublicKey().serialize().toString();
    var avis = 0;
    coffre.surIdentiteNeuve = () => avis++;

    stockage.casse = true;
    final neuve = (await coffre.identiteLocale()).getPublicKey().serialize().toString();

    expect(stockage.remisesAZero, 1, reason: 'la réparation de la bibliothèque doit avoir joué');
    expect(stockage.casse, isFalse);
    expect(neuve, isNot(ancienne));
    expect(avis, 1, reason: 'la pile doit republier la nouvelle identité');
    // Et le coffre fonctionne de nouveau, sans autre réparation.
    expect((await coffre.identiteLocale()).getPublicKey().serialize().toString(), neuve);
    expect(stockage.remisesAZero, 1);
  });

  test('une erreur passagère est retentée et N\'EFFACE RIEN', () async {
    final coffre = CoffreE2ee('doms');
    final avant = (await coffre.identiteLocale()).getPublicKey().serialize().toString();

    stockage.echecsPassagers = 2; // moins que les trois essais
    final apres = (await coffre.identiteLocale()).getPublicKey().serialize().toString();

    expect(apres, avant);
    expect(stockage.remisesAZero, 0);
  });

  test('les accès ordinaires ne demandent jamais la remise à zéro', () async {
    final coffre = CoffreE2ee('doms');
    await coffre.preparer();
    await coffre.identiteLocale();
    await coffre.noterPublie();
    expect(await coffre.dejaPublie(), isTrue);
    expect(stockage.remisesAZero, 0);
  });

  // Le faux stockage des autres essais reste celui de la bibliothèque.
  tearDownAll(() => FlutterSecureStorage.setMockInitialValues({}));
}
