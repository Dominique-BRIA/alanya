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
import 'e2ee_sauvegarde.dart';
import 'e2ee_service.dart';
import 'e2ee_trousseau.dart';

/// Construit la pile de chiffrement pour un compte.
///
/// ⚠️ LIÉE AU COMPTE, PAS À L'APPLICATION. Le coffre préfixe ses clés par
/// l'identifiant : deux comptes sur le même téléphone ne doivent jamais partager
/// une identité Signal, sinon les messages de l'un s'ouvriraient chez l'autre.
class PileE2ee {
  PileE2ee._(this.compteId, this.coffre, this.service, this.fil, this.sauvegarde)
      : trousseau = Trousseau(coffre);

  /// Le compte auquel cette pile appartient.
  ///
  /// 🔴 IL SERT À SAVOIR QUAND LA REBÂTIR. Le fournisseur suit l état
  /// d authentification, qui notifie souvent ; sans cette comparaison, chaque
  /// changement de profil reconstruirait la pile et republierait des clés.
  final String compteId;

  final CoffreE2ee coffre;
  final E2eeService service;
  final E2eeFil fil;

  /// ⚠️ ACTIVÉE PAR DÉFAUT à la connexion, comme sur le web : perdre son
  /// historique en changeant d appareil est un piège que personne ne voit
  /// venir. Un refus, lui, tient — il vit sur le compte.
  final E2eeSauvegarde sauvegarde;

  /// ⚠️ LA SEULE SERRURE QUE NOTRE SERVEUR NE PEUT PAS OUVRIR : son secret ne
  /// lui est jamais transmis, contrairement au mot de passe.
  final Trousseau trousseau;


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
  /// Pourquoi la préparation a échoué, s'il y a lieu.
  ///
  /// 🔴 CE CHAMP EXISTE PARCE QUE LE SILENCE A COÛTÉ DEUX JOURS. `demarrer()`
  /// rattrape tout — et c'est juste : un réseau coupé au lancement ne doit pas
  /// empêcher l'application de s'ouvrir. Mais il ne gardait RIEN.
  ///
  /// Le symptôme visible était alors le message du serveur, « un participant
  /// n'a pas encore publié ses clés », qui désigne le correspondant dans
  /// l'esprit de qui le lit. La vraie cause était ici, et personne ne pouvait
  /// la voir.
  ///
  /// ⚠️ RATTRAPER SANS GARDER, C'EST EFFACER LA SEULE TRACE. Un `catch` qui
  /// ne retient pas ce qu'il attrape ne rend pas l'application robuste : il la
  /// rend muette.
  Object? echecDemarrage;

  Future<void> demarrer() async {
    /*
     * ⚠️ REMIS À ZÉRO ICI, ET NON À LA FIN : la branche « première
     * publication » sort par un `return`, et une remise à zéro placée après
     * aurait laissé traîner l'échec d'un démarrage précédent — en accusant
     * une panne déjà réparée.
     */
    echecDemarrage = null;
    try {
      await coffre.preparer();
      final deviceId = await coffre.deviceId();

      /*
       * 🔴 RATTRAPAGE D'UNE FOIS : NOS MESSAGES DISAIENT VENIR DE L'APPAREIL 1.
       *
       * 🐛 `E2eeFil` avait `monDeviceId = 1` en valeur par défaut, que personne
       * ne remplaçait. Les enveloppes annonçaient donc l'appareil 1 alors que
       * notre identité était publiée sous un numéro tiré au sort : le
       * correspondant a rangé sa session sous `<compte>.1`.
       *
       * ⚠️ CORRIGER L'ANNONCE NE SUFFIT PAS. Nos messages suivants disent
       * venir d'une adresse où il n'a AUCUNE session, et un message ordinaire
       * ne peut pas en ouvrir une — seul un message de type 3 le fait. Il
       * verrait des bulles vides, pour toujours, sans rien pour l'expliquer.
       *
       * 🔴 ON JETTE DONC NOS SESSIONS UNE FOIS. Le prochain message vers chaque
       * correspondant repartira d'un échange X3DH complet, sous la BONNE
       * adresse. On ne perd aucun texte : le clair vit dans le cache et dans
       * l'archive. On ne perd que l'état du ratchet, et c'est ce qu'on veut.
       *
       * ⚠️ L'IDENTITÉ N'EST PAS TOUCHÉE : la recréer déclencherait un
       * avertissement de changement de clé chez tout le monde — une alerte de
       * sécurité pour une opération de maintenance.
       */
      final annonce = int.tryParse(await coffre.lireAppareilAnnonce() ?? '');
      if (annonce != deviceId) {
        await coffre.effacerToutesLesSessions();
        await coffre.noterAppareilAnnonce(deviceId);
      }

      /*
       * ⚠️ UNE SEULE PUBLICATION COMPLÈTE. L'identité ne change pas, et
       * republier cinquante pré-clés à chaque ouverture coûte cher pour rien —
       * c'est ce qui bloquait le démarrage.
       */
      if (!await coffre.dejaPublie()) {
        await service.publierMesCles(deviceId: deviceId);
        await coffre.noterPublie();
        /*
         * ⚠️ MÊME À LA PREMIÈRE PUBLICATION, ON REPREND L'ARCHIVE. C'est
         * précisément le cas d'un téléphone neuf : il n'a aucun historique, et
         * c'est là que la reprise sert le plus.
         */
        await sauvegarde.reprendreAuDemarrage(coffre);
        return;
      }

      /*
       * 🔴 ET ENSUITE, ON DEMANDE AU SERVEUR S'IL EN FAUT D'AUTRES.
       *
       * 🐛 CE RAPPEL MANQUAIT, et le commentaire qui occupait cette place
       * AFFIRMAIT LE CONTRAIRE : « le stock se réapprovisionnera quand il
       * baissera ». Rien ne l'implémentait. Les 50 pré-clés à usage unique
       * s'épuisaient, et au 51ᵉ correspondant plus personne ne pouvait ouvrir
       * de conversation avec ce téléphone — en silence.
       *
       * ⚠️ UN COMMENTAIRE QUI DÉCRIT UNE INTENTION COMME UN FAIT est pire que
       * pas de commentaire : il fait passer la relecture suivante à côté.
       *
       * ⚠️ UN SEUL APPEL, ET IL NE PUBLIE QUE SI LE SERVEUR LE DEMANDE : le
       * coût ordinaire du démarrage reste une requête.
       */
      await service.reapprovisionnerSiNecessaire(deviceId: deviceId);

      /*
       * 🔴 ET ON REPREND L'ARCHIVE, À CHAQUE LANCEMENT.
       *
       * 🐛 `aLaConnexion` ne tourne qu'à la CONNEXION. Quelqu'un qui reste
       * connecté — le cas normal sur un téléphone — n'y repasse jamais. Les
       * messages échangés depuis un autre appareil restaient donc dans
       * l'archive, intacts et hors d'atteinte.
       *
       * ⚠️ LE MOT DE PASSE N'EST PAS DEMANDÉ : la clé maîtresse dort déjà dans
       * le coffre sécurisé. C'est ce qui rend ce rattrapage silencieux.
       */
      await sauvegarde.reprendreAuDemarrage(coffre);
    } catch (e) {
      /*
       * ⚠️ ON NE LÈVE TOUJOURS PAS — l'application doit s'ouvrir. Mais on
       * RETIENT, pour que l'écran qui bute sur l'absence de clés puisse dire
       * ce qui a réellement échoué au lieu de laisser accuser l'autre.
       */
      echecDemarrage = e;
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
      /*
       * 🔴 CE `switch` A COÛTÉ UNE PANNE ENTIÈRE, ET C'EST SON `default` QUI
       * L'A CAUSÉE.
       *
       * 🐛 `PUT` n'avait pas de cas. Il tombait donc dans le `default`, qui
       * envoyait un `PATCH` — sur une route qui n'en expose pas. Réponse : 405,
       * et aucune clé publiée.
       *
       * ⚠️ LE DÉFAUT N'ÉTAIT PAS L'OUBLI, C'ÉTAIT LE `default`. Un oubli se
       * voit : le code ne compile pas, ou il lève. Ici, l'oubli avait une
       * porte de sortie qui prenait silencieusement une AUTRE décision — et
       * qui l'a prise pendant des semaines.
       *
       * 🔴 UN `default` QUI DEVINE EST PIRE QU'UNE ERREUR. On lève désormais :
       * un verbe non prévu doit s'arrêter ici, bruyamment, pas partir sur le
       * réseau déguisé en autre chose.
       *
       * ⚠️ ET LE CONTRÔLE DE ROUTES NE POUVAIT PAS LE VOIR : il comparait le
       * verbe ÉCRIT dans l'appel à celui qu'expose la route, pas le verbe
       * RÉELLEMENT ÉMIS. `outils/contrat_routes.py` vérifie maintenant aussi
       * que chaque verbe utilisé a son cas ici.
       */
      switch (methode) {
        case 'GET':
          return api.get(chemin);
        case 'POST':
          return api.post(chemin, corps ?? const {});
        case 'PUT':
          return api.put(chemin, corps ?? const {});
        case 'PATCH':
          return api.patch(chemin, corps ?? const {});
        case 'DELETE':
          return api.delete(chemin, body: corps);
        default:
          throw ArgumentError('Verbe HTTP non pris en charge : $methode');
      }
    }

    final coffre = CoffreE2ee(compteId);
    final service = E2eeService(coffre, appel);
    return PileE2ee._(
        compteId, coffre, service, E2eeFil(service, appel, coffre.deviceId), E2eeSauvegarde(appel));
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
      return read<PileE2ee?>();
    } catch (_) {
      return null;
    }
  }
}
