import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/core/lien_alanya.dart';

/// Spécification exécutable du format des liens Alanya (QR codes).
/// Lancer avec : flutter test test/lien_alanya_test.dart
void main() {
  group('fabrication', () {
    test('le lien de profil porte l\'ID brut, sans espaces', () {
      expect(lienProfil('82 31 21 87'), 'https://alanyavox.com/u/82312187');
    });
    test('le lien d\'invitation porte le jeton', () {
      expect(
        lienInvitation('AbCdEfGhIjKlMnOpQrStUv'),
        'https://alanyavox.com/i/AbCdEfGhIjKlMnOpQrStUv',
      );
    });
  });

  group('lecture — ce qui est à nous', () {
    test('aller-retour profil', () {
      expect(
        analyserLienAlanya(lienProfil('82312187')),
        const CibleProfil('82312187'),
      );
    });
    test('aller-retour invitation', () {
      const jeton = 'AbCdEfGh-IjKl_MnOpQrSt';
      expect(
        analyserLienAlanya(lienInvitation(jeton)),
        const CibleInvitation(jeton),
      );
    });
    test('ancien QR : le numéro seul', () {
      expect(analyserLienAlanya('82312187'), const CibleProfil('82312187'));
    });
    test('ancien QR : le numéro groupé', () {
      expect(
        analyserLienAlanya(' 82 31 21 87 '),
        const CibleProfil('82312187'),
      );
    });
    test('centre d\'appels à 4 chiffres', () {
      expect(
        analyserLienAlanya('https://alanyavox.com/u/6045'),
        const CibleProfil('6045'),
      );
    });
    test('www, http et barre finale tolérés', () {
      expect(
        analyserLienAlanya('http://www.alanyavox.com/u/82312187/'),
        const CibleProfil('82312187'),
      );
    });
  });

  group('lecture — ce qui ne l\'est pas', () {
    for (final brut in [
      '',
      'abc123', // du texte qui CONTIENT des chiffres
      '12', // trop court
      '12345678901', // trop long
      'https://exemple.com/u/82312187', // autre domaine
      'https://alanyavox.com.pirate.io/u/82312187', // domaine imité
      'https://alanyavox.com/webapp/', // page à nous, mais pas un lien
      'https://alanyavox.com/u/82a12187',
      'https://alanyavox.com/u/82312187/extra',
      'https://alanyavox.com/i/court', // jeton trop court
      'https://alanyavox.com/i/avec%20espace0123456789',
      'alanya://u/82312187', // schéma inconnu
      'WIFI:S:maison;T:WPA;P:secret;;',
    ]) {
      test('« $brut » → nul', () {
        expect(analyserLienAlanya(brut), isNull);
      });
    }
  });
}
