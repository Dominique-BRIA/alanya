/// MA COPIE DU TROUSSEAU D'UN GROUPE — lot 6, cours chapitre 35.
///
/// ⚠️ JUMEAU DE `STAGE-WEB/src/services/e2ee-trousseau-perso.ts` : même forme,
/// mêmes données associées. Une copie déposée par le navigateur s'ouvre sur
/// le téléphone du même compte, et l'inverse (vecteur dans
/// `test/e2ee_trousseau_perso_test.dart`).
///
/// Elle sert au NOUVEAU TÉLÉPHONE : il retrouve les clés de ses groupes sans
/// qu'aucun autre membre soit en ligne, et relit tout l'historique.
///
/// 🔴 CHIFFRÉE PAR LA CLÉ MAÎTRESSE DE L'ARCHIVE PERSONNELLE, que le serveur
/// n'a jamais (elle s'ouvre avec le mot de passe). Le serveur range un chiffré
/// opaque et l'efface au départ du groupe.
///
/// Forme : base64( 0x01 | nonce 12 | AES-256-GCM(clair, aad) + étiquette ).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../core/api_client.dart' show ApiException;
import 'e2ee_coffre.dart';
import 'e2ee_groupe.dart' as g;

/// Les données associées : la copie est liée à SON compte et à SON groupe.
Uint8List aadCopie(String compte, String convId) =>
    Uint8List.fromList(utf8.encode('alanya-trousseau-perso-v1\n$compte\n$convId'));

Uint8List _gcm(bool chiffrer, Uint8List cle, Uint8List nonce, Uint8List aad, Uint8List entree) {
  final c = GCMBlockCipher(AESEngine())
    ..init(chiffrer, AEADParameters(KeyParameter(cle), 128, nonce, aad));
  return c.process(entree);
}

/// Chiffre [clair] avec la clé maîtresse. [nonceImpose] : pour les vecteurs.
String chiffrerCopie(Uint8List maitresse, String clair, Uint8List aad, {Uint8List? nonceImpose}) {
  final r = Random.secure();
  final nonce = nonceImpose ?? Uint8List.fromList(List.generate(12, (_) => r.nextInt(256)));
  final chiffre = _gcm(true, maitresse, nonce, aad, Uint8List.fromList(utf8.encode(clair)));
  return base64.encode([0x01, ...nonce, ...chiffre]);
}

/// L'inverse. LÈVE si la copie est altérée, d'un autre compte ou d'un autre
/// groupe (GCM refuse).
String dechiffrerCopie(Uint8List maitresse, String corps, Uint8List aad) {
  final brut = base64.decode(corps);
  if (brut.length < 1 + 12 + 16 || brut[0] != 0x01) {
    throw const g.GroupeInvalide('copie de trousseau mal formée');
  }
  final clair = _gcm(false, maitresse, Uint8List.sublistView(brut, 1, 13), aad,
      Uint8List.sublistView(brut, 13));
  return utf8.decode(clair);
}

/// Le dépôt et la relecture de mes copies, sur le serveur.
class CopiesTrousseau {
  CopiesTrousseau(this._coffre, this._api, this._compte);

  final CoffreE2ee _coffre;
  final Future<Map<String, dynamic>> Function(
    String methode,
    String chemin,
    Map<String, dynamic>? corps,
  ) _api;
  final String? _compte;

  /// Dépose (ou remplace) ma copie. `false` sans rien faire si l'archive n'est
  /// pas ouverte ici. ⚠️ NE LÈVE JAMAIS : c'est un filet.
  Future<bool> deposer(String convId, List<g.VersionCle> versions) async {
    final moi = _compte;
    if (moi == null || versions.isEmpty) return false;
    try {
      final maitresse = await _coffre.lireMaitresse();
      if (maitresse == null) return false;
      final clair = g.ecrireChargeTrousseau(
          g.Trousseau(convId: convId, motif: 'APPAREIL', versions: versions));
      await _api('PUT', '/api/e2ee/trousseaux/$convId',
          {'corps': chiffrerCopie(maitresse, clair, aadCopie(moi, convId))});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Relit ma copie de ce groupe. `null` : pas de copie, archive fermée, ou
  /// copie refusée.
  Future<List<g.VersionCle>?> lire(String convId) async {
    final moi = _compte;
    if (moi == null) return null;
    final maitresse = await _coffre.lireMaitresse();
    if (maitresse == null) return null;
    final String corps;
    try {
      corps = (await _api('GET', '/api/e2ee/trousseaux/$convId', null))['corps'] as String;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
    try {
      return g.lireChargeTrousseau(dechiffrerCopie(maitresse, corps, aadCopie(moi, convId)), convId)
          .versions;
    } catch (_) {
      return null;
    }
  }

  /// Toutes mes copies, pour un nouveau téléphone : `convId → versions`.
  Future<Map<String, List<g.VersionCle>>> lireToutes() async {
    final moi = _compte;
    final sortie = <String, List<g.VersionCle>>{};
    if (moi == null) return sortie;
    final maitresse = await _coffre.lireMaitresse();
    if (maitresse == null) return sortie;
    final r = await _api('GET', '/api/e2ee/trousseaux', null);
    for (final c in ((r['trousseaux'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final convId = c['convId'] as String;
      try {
        sortie[convId] = g.lireChargeTrousseau(
                dechiffrerCopie(maitresse, c['corps'] as String, aadCopie(moi, convId)), convId)
            .versions;
      } catch (_) {
        // Une copie refusée n'empêche pas de reprendre les autres.
      }
    }
    return sortie;
  }
}
