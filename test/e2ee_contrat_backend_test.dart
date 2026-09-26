import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LE CONTRAT ENTRE LE MOBILE ET LE SERVEUR, ÉPELÉ.
///
/// 🔴 POURQUOI CE TEST EXISTE. Le 26/09/2026, « il est toujours impossible
/// d'activer le chiffrement sur mobile ». La cause n'était ni le protocole ni la
/// cryptographie — les deux sont éprouvés par le banc d'interopérabilité — mais
/// **cinq mots** qui ne correspondaient pas au serveur :
///
///   1. `POST /api/e2ee/cles` alors que la route n'exporte que GET, PUT, DELETE
///      → Next.js répond 405, aucune identité n'est jamais créée en base, et
///      `POST /api/conversations/<id>/e2ee` refuse en `CLES_MANQUANTES` ;
///   2. `prekeySignee.prekeyId` alors que le serveur lit `ps.id` → 400 ;
///   3. `prekeysUniques` alors que le serveur lit `r.prekeys` → **zéro** pré-clé
///      rangée, SANS erreur : `Array.isArray(undefined)` vaut faux ;
///   4. `r['appareils']` alors que la route rend `{ userId, paquets }` → un
///      `null as List` qui LÈVE au lieu de rendre une liste vide ;
///   5. `GET /api/e2ee/enveloppes` sans `?deviceId=`, que la route exige → 400.
///
/// S'y ajoutaient deux défauts du même ordre, côté mobile seul : l'adaptateur de
/// `PileE2ee` transformait TOUT verbe inconnu en `PATCH` (donc un `PUT` devenait
/// un `PATCH`, et la sauvegarde du coffre partait déjà sur le mauvais verbe), et
/// `E2eeFil.monDeviceId` valait `1` par défaut alors que `CoffreE2ee.deviceId()`
/// en tire un ALÉATOIRE — les enveloppes partaient sous un numéro d'appareil que
/// le serveur ne connaissait pas.
///
/// ⚠️ AUCUN DE CES SIX DÉFAUTS NE SE VOIT À LA COMPILATION. Une clé de Map mal
/// orthographiée, un verbe HTTP inventé, un paramètre d'URL oublié : tout cela
/// compile, s'exécute, et échoue sur le téléphone de quelqu'un. `dart analyze`
/// n'a rien à dire sur le sens d'une chaîne.
///
/// ⚠️ LA SOURCE DE VÉRITÉ EST LE DÉPÔT BACKEND, pas ce fichier :
/// `backend-alanya`, branche `feature/vocal-attente-loop`,
/// `src/app/api/e2ee/**` — dont le commentaire d'en-tête de `cles/route.ts`
/// donne l'exemple du corps attendu. Si un nom change là-bas, ce test doit
/// changer ici, et c'est exactement ce qu'il est venu dire.
///
/// Lancer avec : flutter test test/e2ee_contrat_backend_test.dart
void main() {
  String lire(String chemin) {
    final f = File(chemin);
    expect(f.existsSync(), isTrue,
        reason: "le test doit tourner depuis la racine du paquet : $chemin");
    return f.readAsStringSync();
  }

  /// Un appel réseau entier : un peu AVANT l'amorce, jusqu'à la fin de
  /// l'instruction.
  ///
  /// ⚠️ ANCRÉ SUR LA ROUTE, ET NON SUR LA MÉTHODE DART : c'est l'URL qui fait le
  /// contrat. Renommer `publierMesCles` ne doit pas faire taire ce contrôle.
  ///
  /// 🔴 MAIS IL FAUT REMONTER AVANT LA ROUTE. Le verbe s'écrit `api('PUT',
  /// '<route>'…` — il PRÉCÈDE l'URL. Une fenêtre qui partait de l'URL excluait
  /// le verbe, et le contrôle « la publication est en PUT » échouait sur un code
  /// pourtant juste : c'est ce test qui se trompait, pas le source. Soixante
  /// caractères couvrent `await api('PUT', ` sans aller chercher la prose d'un
  /// commentaire voisin, dont les points-virgules fausseraient un retour au
  /// début d'instruction.
  String autourDe(String source, String amorce, {int avant = 60, int fenetre = 900}) {
    final trouve = source.indexOf(amorce);
    expect(trouve, greaterThanOrEqualTo(0),
        reason: "`$amorce` a disparu du source : le contrôle ne garantit plus "
            "rien, il faut le réécrire à la main");
    final debut = trouve - avant < 0 ? 0 : trouve - avant;
    final fin = source.indexOf(';', trouve);
    return source.substring(debut, fin > trouve ? fin : trouve + fenetre);
  }

  final service = lire('lib/services/e2ee/e2ee_service.dart');
  final fil = lire('lib/services/e2ee/e2ee_fil.dart');
  final fournisseur = lire('lib/services/e2ee/e2ee_fournisseur.dart');

  group("Publier ses clés — `/api/e2ee/cles`", () {
    final publication = autourDe(service, "'/api/e2ee/cles'");

    test("le verbe est PUT, le seul que la route exporte pour écrire", () {
      expect(publication, contains("api('PUT'"),
          reason: "🔴 la route n'exporte que GET, PUT et DELETE. Un POST y "
              "répond 405, et c'est ce 405 qui faisait « impossible d'activer "
              "le chiffrement » : sans identité en base, l'activation refuse "
              "en CLES_MANQUANTES");
      expect(publication, isNot(contains("api('POST'")));
    });

    test("la pré-clé signée porte `id`, comme le serveur la lit", () {
      expect(publication, contains("'id': signee.id"),
          reason: "le serveur lit `ps.id` ; un `prekeyId` rend `undefined`, et "
              "`entier(undefined)` vaut faux → 400 « prekeySignee incomplète »");
      expect(publication, isNot(contains("'prekeyId': signee.id")));
    });

    test("le lot s'appelle `prekeys`, et chaque clé porte `id`", () {
      expect(publication, contains("'prekeys':"),
          reason: "🔴 LE PIÈGE LE PLUS TRAÎTRE DES CINQ : `prekeysUniques` ne "
              "provoque AUCUNE erreur. `Array.isArray(undefined)` vaut faux, "
              "donc le serveur range ZÉRO pré-clé et répond 201. Le stock reste "
              "vide et chaque session ouverte avec cet appareil perd son "
              "quatrième calcul Diffie-Hellman, silencieusement");
      expect(publication, isNot(contains("'prekeysUniques':")));
      expect(publication, contains("'id': p.id"),
          reason: "dans le lot aussi, le serveur lit `p.id`");
    });

    test("ce qui part est PUBLIC — aucune clé privée dans ce corps", () {
      /*
       * ⚠️ LE SEUL CONTRÔLE DE SÉCURITÉ DE CE FICHIER, et il ne peut pas être
       * fait par le serveur : une clé privée ressemble trait pour trait à une
       * clé publique. Tout ce qui transite ici doit sortir d'un `.getPublicKey()`
       * ou d'une signature — jamais d'un `getPrivateKey()`.
       */
      expect(publication, isNot(contains('getPrivateKey')),
          reason: "🔴 une clé privée qui atteint le serveur n'est plus un "
              "serveur de bout en bout");
      expect(publication, contains('getPublicKey()'));
    });
  });

  group("Lire les clés d'un correspondant — `/api/e2ee/cles/<userId>`", () {
    test("la réponse se lit dans `paquets`", () {
      /*
       * ⚠️ SUR TOUT LE FICHIER, ET NON SUR UNE FENÊTRE : la lecture se fait dans
       * l'instruction qui SUIT l'appel (`final r = await api(…);` puis
       * `final paquets = (r['paquets'] …)`). Une fenêtre arrêtée au premier
       * point-virgule ne contiendrait ni l'un ni l'autre, et le contrôle
       * passerait au vert sans rien avoir regardé.
       */
      expect(autourDe(service, "'/api/e2ee/cles/\$pairId'"), contains("api('GET'"));
      expect(service, isNot(contains("r['appareils']")),
          reason: "🔴 la route rend `ok({ userId, paquets })`. Un "
              "`null as List` ne rend pas une liste vide, il LÈVE : chaque "
              "ouverture de session échouait avant d'avoir lu une clé, et "
              "`envoyer` n'atteignait jamais son « Aucun appareil chiffré chez "
              "ce correspondant », pourtant écrit pour ce cas-là");
      expect(service, contains("r['paquets']"));
    });

    test("au RETOUR les noms diffèrent de l'ALLER — et c'est voulu", () {
      /*
       * ⚠️ ASYMÉTRIE RÉELLE DU CONTRAT, à ne pas « corriger » par symétrie :
       * à l'aller le serveur LIT `prekeySignee.id` et `prekeys[].id` ; au retour
       * il REND `prekeySignee.prekeyId` et `prekeyUnique.prekeyId`, parce que la
       * route projette directement les colonnes Prisma. Chercher les mêmes noms
       * dans les deux sens ferait régresser l'un des deux.
       */
      expect(service, contains("p['prekeySignee']"));
      expect(service, contains("p['prekeyUnique']"));
      expect(service, contains("signee['prekeyId']"));
      expect(service, contains("unique['prekeyId']"));
    });
  });

  group("Relever ses enveloppes — `/api/e2ee/enveloppes`", () {
    test("la relève annonce QUEL appareil relève", () {
      final releve = autourDe(fil, "'/api/e2ee/enveloppes?deviceId=");
      expect(releve, contains('?deviceId='),
          reason: "🔴 la route répond 400 « « deviceId » est requis » sans lui, "
              "et aucun message chiffré n'a jamais pu être relevé sur mobile");
      expect(releve, contains('monDeviceId'));
    });

    test("l'acquittement reste un DELETE avec les ids en URL", () {
      expect(fil, contains("'/api/e2ee/enveloppes?ids=\$ids'"));
      expect(fil, contains("_api('DELETE'"));
    });

    test("on acquitte APRÈS avoir déchiffré, jamais avant", () {
      final corps = fil.substring(fil.indexOf('Future<({List<MessageClair>'));
      expect(corps.indexOf('dechiffrer'), lessThan(corps.indexOf('?ids=')),
          reason: "🔴 une enveloppe acquittée est définitivement perdue : le "
              "ratchet a avancé et la clé du message est détruite. Acquitter "
              "d'abord ferait disparaître un message qu'on n'a pas su lire");
    });
  });

  group("Le numéro d'appareil — un seul fait, une seule source", () {
    test("plus aucune valeur par défaut à 1", () {
      expect(fil, isNot(contains('monDeviceId = 1')),
          reason: "🔴 `CoffreE2ee.deviceId()` tire un numéro ALÉATOIRE dans "
              "1..2³¹-1. Publier sous ce numéro et envoyer sous le numéro 1 "
              "fait ouvrir au destinataire une session vers une adresse qui "
              "n'existe chez personne : message illisible, sans erreur qui "
              "nomme la cause");
      expect(fil, contains('_coffre.deviceId()'),
          reason: "le numéro envoyé doit être CELUI qui a été publié");
    });
  });

  group("L'adaptateur de verbes — `PileE2ee.pour`", () {
    test("PUT a son propre cas", () {
      final adapteur =
          fournisseur.substring(fournisseur.indexOf('switch (methode)'));
      expect(adapteur, contains("case 'PUT':"),
          reason: "🔴 DEUX routes du chiffrement s'écrivent en PUT — "
              "/api/e2ee/cles et /api/e2ee/coffre. Sans ce cas, elles partaient "
              "en PATCH sur des routes qui ne l'exportent pas : 405");
      expect(adapteur, contains('api.put('));
    });

    test("un verbe inconnu LÈVE, et ne devine plus", () {
      final adapteur =
          fournisseur.substring(fournisseur.indexOf('switch (methode)'));
      expect(adapteur, isNot(contains('default:\n          return api.patch')),
          reason: "🔴 C'ÉTAIT LE DÉFAUT LE MIEUX CACHÉ : un repli silencieux "
              "sur un autre verbe ne se voit nulle part. La requête part, elle "
              "échoue, et l'écran dit « le chiffrement n'a pas pu être activé » "
              "sans qu'aucun journal ne nomme le verbe");
      expect(adapteur, contains('throw ArgumentError'));
    });
  });

  group("Le refus d'activation est DIT, pas avalé", () {
    test("les deux écrans montrent le motif du serveur", () {
      /*
       * ⚠️ LA ROUTE ÉCRIT SES REFUS POUR ÊTRE LUS : `HORS_PERIMETRE`,
       * `GROUPE_NON_SUPPORTE`, `CLES_MANQUANTES`, chacun avec une phrase
       * française, et son commentaire précise que « l'écran a besoin de le
       * DIRE, pas seulement de griser un bouton ».
       *
       * 🔴 LES DEUX REFUS NE SE RÉPARENT PAS DE LA MÊME FAÇON, et un texte
       * générique les confond : un fil d'agents est hors périmètre PAR
       * CONCEPTION et ne le sera jamais ; un correspondant qui n'a pas encore
       * ouvert l'application se débloque tout seul. Sans le motif, l'utilisateur
       * retente indéfiniment un geste qui ne peut pas réussir.
       */
      for (final ecran in [
        'lib/features/chat/screens/chat_screen.dart',
        'lib/features/contacts/screens/contact_info_screen.dart',
      ]) {
        final source = lire(ecran);
        expect(source, contains('on ApiException catch (e)'),
            reason: "$ecran avale le motif du serveur");
        expect(source, contains('showAppSnackBar(e.message)'),
            reason: "$ecran doit montrer la phrase écrite par la route");
      }
    });
  });
}
