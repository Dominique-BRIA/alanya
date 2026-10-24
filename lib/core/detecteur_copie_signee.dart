import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// UNE COPIE SIGNÉE NE REPART PAS EN « SENSIBLE » (24/10/2026, demande du user).
///
/// A envoie un document sensible à B. B le télécharge : la copie porte
/// l'empreinte de B (bords et métadonnées). Si B pouvait la renvoyer comme
/// document SENSIBLE — à l'un de ses faux comptes, par exemple —, le
/// téléchargement suivant écrirait par-dessus les métadonnées du faux compte,
/// et la trace de B, le vrai fuiteur, serait perdue.
///
/// Une copie signée ne peut donc repartir qu'en document ORDINAIRE : rien ne
/// la re-signe, ses métadonnées restent celles de B.
///
/// COMMENT ON LA RECONNAÎT. La signature écrit des noms de champs en clair
/// dans le fichier, quel que soit son format : « Empreinte numerique » (EXIF,
/// iTXt d'un PNG, éléments d'une vidéo), « Empreinte#20numerique » (nom
/// encodé dans le dictionnaire Info d'un PDF), et, pour les copies sorties du
/// 22 au 24/10, « AlanyaTrace » et l'espace de noms vidéo
/// « com.alanya237.work ». Les deux clients écrivent ces champs SANS
/// compression (le web l'impose au PDF : `useObjectStreams: false`), ils se
/// retrouvent donc tels quels dans les octets.
///
/// ⚠️ LA LIMITE : quelqu'un qui réenregistre l'image ou le PDF dans un autre
/// logiciel peut effacer les métadonnées. La signature visible aux bords,
/// elle, reste sur le document.
class DetecteurCopieSignee {
  DetecteurCopieSignee._();

  static final _marques = [
    for (final m in const [
      'Empreinte numerique',
      'Empreinte#20numerique',
      'AlanyaTrace',
      'com.alanya237.work',
    ])
      Uint8List.fromList(latin1.encode(m)),
  ];

  /// Ces octets sont-ils une copie signée d'un document sensible ?
  static bool contientSignature(Uint8List octets) {
    for (final m in _marques) {
      if (_indexDe(octets, m) >= 0) return true;
    }
    return false;
  }

  /// La même chose, hors du fil de l'interface : une vidéo de 300 Mo se
  /// parcourt en une ou deux secondes, l'écran ne doit pas se figer.
  static Future<bool> estCopieSignee(Uint8List octets) =>
      octets.length < (1 << 20)
      ? Future.value(contientSignature(octets))
      : compute(contientSignature, octets);

  static int _indexDe(Uint8List d, Uint8List m) {
    final premier = m[0];
    final fin = d.length - m.length;
    for (var i = 0; i <= fin; i++) {
      if (d[i] != premier) continue;
      var j = 1;
      while (j < m.length && d[i + j] == m[j]) {
        j++;
      }
      if (j == m.length) return i;
    }
    return -1;
  }
}
