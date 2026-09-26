/// LE CHIFFREMENT, RENDU ACCESSIBLE AUX ÉCRANS.
///
/// 🔴 CE FICHIER EST CE QUI MANQUAIT POUR QUE LES ÉCRANS EXISTENT VRAIMENT. Les
/// services et les widgets étaient écrits, mais rien ne les reliait : aucun
/// écran ne pouvait obtenir un `E2eeService`, donc aucun ne pouvait l'afficher.
///
/// ⚠️ IL SUIT LE PATRON DÉJÀ EN PLACE — `provider` et `context.read<T>()`, comme
/// `ChatRepository` ou `ContactsRepository`. En inventer un autre aurait obligé
/// à tenir deux façons de récupérer un service dans la même application.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/authed_api.dart';
import 'e2ee_coffre.dart';
import 'e2ee_fil.dart';
import 'e2ee_journal.dart';
import 'e2ee_service.dart';

/// Construit la pile de chiffrement pour un compte.
///
/// ⚠️ LIÉE AU COMPTE, PAS À L'APPLICATION. Le coffre préfixe ses clés par
/// l'identifiant : deux comptes sur le même téléphone ne doivent jamais partager
/// une identité Signal, sinon les messages de l'un s'ouvriraient chez l'autre.
class PileE2ee {
  PileE2ee._(this.compteId, this.coffre, this.service, this.fil);

  /// Le compte que cette pile chiffre — voir `main.dart`, qui garde UNE pile
  /// par compte et s'en sert pour ne pas la reconstruire à chaque
  /// notification d'authentification.
  final String compteId;

  final CoffreE2ee coffre;
  final E2eeService service;
  final E2eeFil fil;

  /// Démarrage en cours — le démarrage est demandé à la fois par
  /// l'authentification et par la reconnexion, et les deux peuvent tomber
  /// ensemble. Sans cette garde, deux publications partiraient en même temps
  /// avec deux réassorts concurrents.
  bool _enCours = false;

  /// Les clés de ce démarrage ont bien été publiées.
  ///
  /// 🔴 C'EST CE FANION QUI DÉCLENCHE LE RÉESSAI, pas le fanion persistant du
  /// coffre : celui-là dit « publié un jour », celui-ci « publié depuis
  /// l'ouverture de l'application ». Un démarrage hors réseau laisse le
  /// premier à vrai et le second à faux — et la reconnexion réessaie.
  bool _publie = false;
  bool get publie => _publie;


  /// Prépare cet appareil et publie ses clés publiques.
  ///
  /// 🐛 CE DÉMARRAGE MANQUAIT, ET C'ÉTAIT LA CAUSE DU DÉFAUT SIGNALÉ : « quand
  /// une personne n'est pas en ligne, aucun message ne part, on dit qu'il n'y a
  /// pas les clés ».
  ///
  /// Rien n'appelait `publierMesCles()`. Le mobile n'avait donc JAMAIS publié
  /// d'identité ni de pré-clés, et personne ne pouvait lui écrire — en ligne ou
  /// non. La présence n'y était pour rien : les clés n'existaient pas.
  ///
  /// ⚠️ X3DH EXISTE PRÉCISÉMENT POUR ÉCRIRE À QUELQU'UN D'ABSENT. Si les clés
  /// manquent quand le correspondant est hors ligne, ce n'est jamais le
  /// protocole qui est en cause : ou elles n'ont pas été publiées, ou on les
  /// retire à tort.
  ///
  /// ⚠️ APPELÉ À CHAQUE DÉMARRAGE, et c'est voulu : l'identité n'est créée
  /// qu'une fois — `preparer` sort si elle existe — mais les PRÉ-CLÉS
  /// s'épuisent, chacune ne servant qu'une fois. Les republier réapprovisionne.
  ///
  /// ⚠️ NE LÈVE JAMAIS. Un réseau coupé au lancement ne doit pas empêcher
  /// l'application de s'ouvrir ; on réessaiera au démarrage suivant.
  Future<void> demarrer() async {
    if (_enCours) return;
    _enCours = true;
    try {
      await coffre.preparer();
      final id = await coffre.deviceId();
      // 🔴 LE FIL DOIT SIGNER DE SON VRAI NUMÉRO : sans cette ligne, les
      // enveloppes partent avec l'appareil `1` du constructeur alors que les
      // clés sont publiées sous le numéro tiré au sort — le serveur ne peut
      // ni filtrer nos propres enveloppes, ni dire au destinataire quelle
      // session ouvrir.
      fil.monDeviceId = id;
      await service.publierMesCles(deviceId: id);
      _publie = true;
    } catch (e) {
      E2eeJournal.note('échec démarrage pile E2EE: $e');
      // Sans clés publiées, l'écran de conversation dira « aucun appareil
      // chiffré chez ce correspondant ». La reconnexion réessaiera.
    } finally {
      _enCours = false;
    }
  }

  static PileE2ee pour(AuthedApi api, String compteId) {
    /*
     * ⚠️ L'ADAPTATEUR EXISTE PARCE QUE LES SERVICES NE CONNAISSENT PAS
     * `AuthedApi`. Ils reçoivent une fonction, ce qui les rend exécutables en
     * Dart pur — c'est ainsi que le banc d'interopérabilité les éprouve sans
     * Flutter ni serveur.
     */
    Future<Map<String, dynamic>> appel(
      String methode,
      String chemin,
      Map<String, dynamic>? corps,
    ) {
      switch (methode) {
        case 'GET':
          return api.get(chemin);
        case 'POST':
          return api.post(chemin, corps ?? const {});
        case 'DELETE':
          return api.delete(chemin, body: corps);
        default:
          return api.patch(chemin, corps ?? const {});
      }
    }

    final coffre = CoffreE2ee(compteId);
    final service = E2eeService(coffre, appel);
    return PileE2ee._(compteId, coffre, service, E2eeFil(service, appel));
  }
}

/// Le raccourci que les écrans utilisent.
///
/// ⚠️ REND `null` PLUTÔT QUE DE LEVER quand la pile n'est pas montée. Un écran
/// ouvert avant la connexion ne doit pas planter : il cache simplement ce qui
/// touche au chiffrement.
extension E2eeContexte on BuildContext {
  PileE2ee? get e2ee {
    try {
      // ⚠️ NULLABLE : le fournisseur existe toujours, mais il rend `null`
      // tant que personne n'est connecté — voir le `ProxyProvider` de
      // `main.dart`.
      return read<PileE2ee?>();
    } catch (_) {
      return null;
    }
  }
}
