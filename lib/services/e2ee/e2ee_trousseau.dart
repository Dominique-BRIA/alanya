/// LA SERRURE « TROUSSEAU », CÔTÉ MOBILE.
///
/// 🔴 LA SEULE DES TROIS QUI NE DEMANDE RIEN À RETENIR. Face ID, Touch ID, ou le
/// code de verrouillage : le geste que les gens font déjà tous les jours, et
/// l'archive s'ouvre.
///
/// ── CE QU'ELLE EST, ET CE QU'ELLE N'EST PAS ─────────────────────────
///
/// Le web dérive son secret d'une clé d'accès WebAuthn, dont la clé privée ne
/// sort jamais du matériel. Le mobile n'a pas d'équivalent aussi propre : on
/// TIRE un secret au sort et on le range dans le coffre matériel, derrière une
/// vérification biométrique.
///
/// ⚠️ LA DIFFÉRENCE EST RÉELLE ET IL FAUT LA DIRE. Sur le web, le secret est
/// RECALCULÉ à chaque fois et n'existe nulle part. Ici il est STOCKÉ — protégé
/// par le matériel et par la biométrie, mais stocké. Un appareil déverrouillé et
/// compromis le rend accessible ; la clé d'accès du web, non.
///
/// ⚠️ CE QUE CELA VAUT QUAND MÊME : notre serveur ne voit jamais ce secret,
/// contrairement au mot de passe qu'il reçoit à chaque connexion. Cette serrure
/// reste la plus forte des trois face à un serveur compromis.
library;

import 'dart:convert';
import 'dart:math';

import 'package:local_auth/local_auth.dart';

import 'e2ee_coffre.dart';

class Trousseau {
  Trousseau(this._coffre);

  final CoffreE2ee _coffre;
  final _auth = LocalAuthentication();

  /// L'appareil sait-il vérifier son porteur ?
  ///
  /// ⚠️ ON NE PROPOSE PAS CE QU'ON NE PEUT PAS TENIR. Un bouton qui échouerait
  /// après une demande de Face ID est pire que pas de bouton : la personne croit
  /// avoir raté quelque chose.
  Future<bool> disponible() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Demande la vérification, puis rend le secret de cet appareil.
  ///
  /// ⚠️ LE SECRET EST TIRÉ AU SORT À LA PREMIÈRE DEMANDE, puis relu. 256 bits :
  /// il ne se devine pas, et c'est pourquoi sa serrure n'a besoin que d'UNE
  /// itération de dérivation — l'étirement compense un manque d'entropie, et il
  /// n'y en a pas ici.
  ///
  /// ⚠️ REND `null` SI L'UTILISATEUR ANNULE. Refuser Face ID n'est pas une
  /// panne : c'est une réponse. La traiter comme une erreur ferait afficher un
  /// message rouge à quelqu'un qui a simplement changé d'avis.
  Future<String?> secret({required String raison}) async {
    bool ok;
    try {
      ok = await _auth.authenticate(
        localizedReason: raison,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return null;
    }
    if (!ok) return null;

    final garde = await _coffre.lireSecretTrousseau();
    if (garde != null) return garde;

    final s = base64.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _coffre.rangerSecretTrousseau(s);
    return s;
  }
}
