/// LE PARTAGE DE SHAMIR — contacts de récupération (27/11/2026, chantier 2).
///
/// 🔴 JUMEAU DE `STAGE-WEB/src/services/e2ee-shamir.ts` : mêmes octets pour
/// les mêmes coefficients (vecteur figé dans `test/e2ee_shamir_test.dart`).
///
/// Chaque octet du secret est le terme constant d'un polynôme de degré k − 1 à
/// coefficients tirés au sort, dans le corps à 256 éléments d'AES (polynôme
/// x⁸ + x⁴ + x³ + x + 1). La part d'indice x est la valeur du polynôme en x.
/// Avec k parts, l'interpolation de Lagrange en 0 rend le secret ; avec moins,
/// toutes les valeurs restent également possibles — une part seule ne dit rien.
///
/// ⚠️ PAS D'INDICE 0 : la valeur en 0 EST le secret.
library;

import 'dart:math';
import 'dart:typed_data';

class PartShamir {
  const PartShamir(this.indice, this.valeur);

  /// L'abscisse, de 1 à 255.
  final int indice;
  final Uint8List valeur;
}

/// Produit dans GF(2⁸), réduction par 0x11b.
int multiplierGf(int a, int b) {
  var p = 0;
  while (b != 0) {
    if (b & 1 != 0) p ^= a;
    final haut = a & 0x80;
    a = (a << 1) & 0xff;
    if (haut != 0) a ^= 0x1b;
    b >>= 1;
  }
  return p;
}

/// Inverse dans GF(2⁸) : a²⁵⁴.
int inverserGf(int a) {
  if (a == 0) throw ArgumentError("zéro n'a pas d'inverse");
  var r = 1;
  var x = a;
  var e = 254;
  while (e != 0) {
    if (e & 1 != 0) r = multiplierGf(r, x);
    x = multiplierGf(x, x);
    e >>= 1;
  }
  return r;
}

Uint8List _aleaSur(int longueur) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(longueur, (_) => r.nextInt(256)));
}

/// Partage [secret] en [n] parts dont [k] suffisent. [alea] : pour les
/// vecteurs seulement — il rend les (k − 1) × longueur coefficients.
List<PartShamir> partagerSecret(
  Uint8List secret,
  int n,
  int k, {
  Uint8List Function(int longueur)? alea,
}) {
  if (k < 2 || n < k || n > 255) throw ArgumentError('partage impossible');
  final coef = (alea ?? _aleaSur)(secret.length * (k - 1));
  final parts = <PartShamir>[];
  for (var x = 1; x <= n; x++) {
    final valeur = Uint8List(secret.length);
    for (var i = 0; i < secret.length; i++) {
      // Horner : a(k−1)·x^(k−1) + … + a1·x + secret[i].
      var y = 0;
      for (var j = k - 2; j >= 0; j--) {
        y = multiplierGf(y, x) ^ coef[j * secret.length + i];
      }
      valeur[i] = multiplierGf(y, x) ^ secret[i];
    }
    parts.add(PartShamir(x, valeur));
  }
  return parts;
}

/// Rend le secret à partir de parts d'indices distincts (autant que le seuil).
Uint8List assemblerSecret(List<PartShamir> parts) {
  if (parts.length < 2) throw ArgumentError('il faut au moins deux parts');
  if (parts.map((p) => p.indice).toSet().length != parts.length) {
    throw ArgumentError('indices en double');
  }
  final longueur = parts.first.valeur.length;
  final secret = Uint8List(longueur);
  for (final pj in parts) {
    // Coefficient de Lagrange en 0 : Π x_m / (x_m − x_j), soustraction = XOR.
    var num = 1;
    var den = 1;
    for (final pm in parts) {
      if (identical(pm, pj)) continue;
      num = multiplierGf(num, pm.indice);
      den = multiplierGf(den, pm.indice ^ pj.indice);
    }
    final l = multiplierGf(num, inverserGf(den));
    for (var i = 0; i < longueur; i++) {
      secret[i] ^= multiplierGf(pj.valeur[i], l);
    }
  }
  return secret;
}
