import 'dart:async';
import 'dart:io';

import 'package:alanya/core/api_client.dart';
import 'package:alanya/core/nature_echec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Un échec de connexion doit dire QUI est en cause.
///
/// 🔴 LE DÉFAUT CORRIGÉ ICI N'EST PAS RÉSEAU, IL EST DE LANGUE. Le 26/09/2026,
/// « lorsque je veux me connecter on me dit impossible de contacter le serveur ».
/// Le texte venait d'un `catch (_)` qui n'avait RIEN regardé : le seul cas où
/// l'application sait que le serveur a répondu est une `ApiException`, parce
/// qu'elle seule porte un code de statut. Tout le reste — certificat refusé,
/// réponse 200 illisible, écriture de coffre qui échoue — héritait de la même
/// accusation.
///
/// ⚠️ LE COÛT N'EST PAS ESTHÉTIQUE. « Impossible de contacter le serveur » envoie
/// l'utilisateur vérifier sa box et le développeur relire `ApiClient`, alors que
/// la panne était ailleurs. Un message d'erreur faux coûte plus cher qu'aucun
/// message : il oriente la réparation dans la mauvaise direction.
///
/// Lancer avec : flutter test test/connexion_classifiee_test.dart
void main() {
  group("Le serveur n'a PAS répondu — les deux seules vraies pannes réseau", () {
    test("rien n'est sorti de l'appareil : injoignable", () {
      // DNS : le nom ne résout pas. C'est le seul cas où le texte historique
      // était vrai.
      final dns = SocketException(
          "Failed host lookup: 'alanyavox.com' "
          "(OS Error: No address associated with hostname, errno = 7)");
      expect(natureEchec(dns), NatureEchec.injoignable);
      expect(cleEchecDe(dns), 'server_unreachable');

      // Port fermé / service arrêté.
      final refuse = SocketException("Connection refused",
          osError: const OSError("Connection refused", 111),
          address: InternetAddress.loopbackIPv4,
          port: 443);
      expect(natureEchec(refuse), NatureEchec.injoignable);
    });

    test("la requête est partie, rien n'est revenu : sans réponse", () {
      final muet = TimeoutException("le serveur n'a pas répondu", ApiClient.borneJson);
      expect(natureEchec(muet), NatureEchec.sansReponse);
      expect(cleEchecDe(muet), 'server_no_answer',
          reason: "⚠️ PAS `server_unreachable` : le serveur est JOIGNABLE, il ne "
              "RÉPOND PAS. Ce sont deux réparations différentes — l'une est "
              "côté réseau, l'autre côté process backend");
    });
  });

  group("LE PIÈGE — le serveur a répondu, et on l'accusait quand même", () {
    test("un certificat refusé n'est PAS un serveur injoignable", () {
      // 🔴 LE CAS LE PLUS PROBABLE DU RAPPORT. Nginx qui sert le certificat sans
      // sa chaîne d'intermédiaires : le navigateur la complète tout seul (AIA),
      // `dart:io` non — l'application échoue là où le site web fonctionne, et le
      // serveur est parfaitement vivant.
      final tls = HandshakeException(
          "Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: "
          "unable to get local issuer certificate)");
      expect(natureEchec(tls), NatureEchec.tls);
      expect(cleEchecDe(tls), 'tls_error');
    });

    test("…et `package:http` le recopie dans une ClientException", () {
      /*
       * ⚠️ C'EST LA RAISON POUR LAQUELLE LE TEXTE PASSE AVANT LE TYPE. `http`
       * rattrape l'erreur de pile et relance `ClientException` dont le message
       * recopie l'original : un échec de certificat arrive typé dans la famille
       * « réseau ». Un classement par type seul le rangerait en injoignable.
       */
      final enveloppe = http.ClientException(
        "HandshakeException: Handshake error in client "
        "(OS Error: CERTIFICATE_VERIFY_FAILED)",
        Uri.parse("https://alanyavox.com/api/auth/login"),
      );
      expect(enveloppe.runtimeType.toString(), 'ClientException');
      expect(natureEchec(enveloppe), NatureEchec.tls,
          reason: "le type dit réseau, le texte dit certificat : c'est le texte "
              "qui a raison");

      // La même enveloppe, sur une vraie coupure, reste injoignable.
      final coupure = http.ClientException(
        "SocketException: Failed host lookup: 'alanyavox.com'",
        Uri.parse("https://alanyavox.com/api/auth/login"),
      );
      expect(natureEchec(coupure), NatureEchec.injoignable);
    });

    test("une réponse 200 illisible n'est PAS un serveur injoignable", () {
      /*
       * ⚠️ Cas réel d'un déploiement backend qui change un champ :
       * `AuthUser.fromJson` reçoit `null` là où il attendait une Map.
       *
       * 🔴 L'ERREUR EST PROVOQUÉE, PAS IMITÉE. `TypeError` se construit par le
       * runtime (c'est `_TypeError` en pratique) : un `TypeError()` écrit à la
       * main testerait un nom de type qui n'existe pas sur un vrai téléphone, et
       * passerait au vert pour rien.
       */
      final reponse = <String, dynamic>{"user": null};
      Object? contrat;
      try {
        final user = reponse["user"] as Map<String, dynamic>;
        contrat = Exception("jamais atteint — ${user.length}");
      } catch (e) {
        contrat = e;
      }
      expect(contrat!.runtimeType.toString(), contains("TypeError"),
          reason: "le test doit bien exercer un vrai échec de type, sinon il ne "
              "garantit rien sur ce que le classement fera du cas réel");
      expect(natureEchec(contrat), NatureEchec.reponseInattendue);

      // Un corps qui n'est pas du JSON — une page HTML d'erreur, par exemple.
      final corps = FormatException("Unexpected character (at character 1)\n<");
      expect(natureEchec(corps), NatureEchec.reponseInattendue);
      expect(cleEchecDe(corps), 'unexpected_answer');
    });

    test("une ApiException prouve que le serveur a répondu", () {
      final repondu = ApiException(503, "Erreur serveur 503");
      expect(natureEchec(repondu), NatureEchec.reponseInattendue,
          reason: "🔴 c'est la SEULE erreur du classement qui porte un code de "
              "statut — donc la seule qui prouve un aller-retour complet");
    });

    test("ce qui vient de l'appareil n'accuse pas le serveur", () {
      // Le coffre sécurisé qui refuse d'écrire, un droit manquant, une base
      // verrouillée : le serveur n'y est pour rien.
      final coffre = Exception("UnknownException (OS Error: Keystore unavailable)");
      expect(natureEchec(coffre), NatureEchec.local);
      expect(cleEchecDe(coffre), 'device_error');
    });
  });

  group("Toute nature a sa clé, et le repli n'accuse jamais le serveur", () {
    test("les cinq natures sont couvertes", () {
      final vus = <NatureEchec>{
        natureEchec(SocketException("Connection refused")),
        natureEchec(HandshakeException("certificate")),
        natureEchec(TimeoutException("muet")),
        natureEchec(ApiException(500, "boom")),
        natureEchec(Exception("autre chose")),
      };
      expect(vus, NatureEchec.values.toSet(),
          reason: "une nature jamais atteinte par ce test est une nature dont le "
              "texte n'a jamais été vérifié");
    });

    test("dans le doute, on accuse l'appareil", () {
      expect(natureEchec(Exception("inconnu")), NatureEchec.local,
          reason: "⚠️ LE REPLI EST UN CHOIX, pas un oubli : un « serveur "
              "injoignable » non mérité fait perdre une journée à quelqu'un "
              "d'autre, un « l'application n'a pas pu terminer » lui fait "
              "retenter dix secondes");
      expect(cleEchecDe(Exception("inconnu")), isNot('server_unreachable'));
    });
  });

  /*
   * ⚠️ LES DEUX CONTRÔLES CI-DESSOUS LISENT LE CODE SOURCE, comme
   * `l10n_parite_test.dart`. C'est voulu : ils portent sur la FORME d'un chemin
   * d'exécution, que `dart analyze` ne voit pas — un `await http.post(...)` sans
   * plafond compile très bien, et un `catch (_)` qui ment compile très bien.
   */
  group("Contrôles de forme", () {
    test("aucune requête JSON ne part sans plafond", () {
      final source = File("lib/core/api_client.dart").readAsStringSync();

      final directs = RegExp(r"await http\.(get|post|put|patch|delete)\(")
          .allMatches(source)
          .length;
      expect(directs, 0,
          reason: "🔴 `package:http` ne borne RIEN par défaut : un serveur qui "
              "accepte la connexion puis se tait laisse le Future en suspens "
              "pour toujours, et le `finally` du bouton « Se connecter » ne "
              "tourne jamais. Toute requête JSON doit passer par `_envoi`, qui "
              "pose `borneJson`");

      // Cinq verbes, cinq passages par le plafond — et NON un seul, qui
      // laisserait une future méthode repartir sans lui.
      final bornes = RegExp(r"_envoi\(\(\) =>\s*\n?\s*http\.").allMatches(source);
      expect(bornes.length, 5,
          reason: "post, get, patch, put, delete : chacun doit passer par "
              "`_envoi`. Trouvé ${bornes.length}");
      expect(source, contains("borneJson"),
          reason: "le plafond doit être nommé, et non répété en cinq durées "
              "littérales qui divergeront un jour");
    });

    test("les uploads restent hors plafond, exprès", () {
      final source = File("lib/core/api_client.dart").readAsStringSync();
      expect(source, contains("await http.Response.fromStream(streamed)"),
          reason: "⚠️ un média de cinquante Mo sur une liaison lente met "
              "légitimement plus de vingt secondes, et il a DÉJÀ une barre de "
              "progression pour dire qu'il avance. Borner ce qui annonce sa "
              "progression, c'est couper un envoi qui n'est pas perdu");
    });

    test("aucun écran d'authentification n'accuse le réseau sans regarder", () {
      final ecrans = Directory("lib/features/auth/screens")
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".dart"));
      expect(ecrans.length, greaterThanOrEqualTo(6),
          reason: "le contrôle doit porter sur tout le parcours : inscription, "
              "code de confirmation, choix du pays, connexion, reprise");

      for (final ecran in ecrans) {
        final source = ecran.readAsStringSync();
        /*
         * ⚠️ DEUX CLÉS, ET NON UNE. Le parcours de reprise accusait le réseau
         * sous `network_error_retry` là où l'inscription l'accusait sous
         * `server_unreachable` : même aveuglement, deux textes. Un contrôle
         * ancré sur une seule clé aurait laissé l'autre en place.
         */
        final aveugle = RegExp(
                r"catch\s*\(\s*_\s*\)[\s\S]{0,200}?(server_unreachable|network_error_retry)")
            .allMatches(source);
        expect(aveugle, isEmpty,
            reason: "${ecran.path} rattrape sans regarder et accuse le réseau : "
                "il doit passer par `traceEchecConnexion(e)` + `cleEchecDe(e)`");
      }
    });
  });
}
