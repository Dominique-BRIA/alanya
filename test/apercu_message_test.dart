import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/models/message_payload.dart';

/// Spécification exécutable de l'aperçu d'une ligne d'un message.
///
/// Il s'affiche à QUATRE endroits — citation d'une réponse, bandeau du message
/// épinglé, barre au-dessus du champ de saisie, dernier message de la liste des
/// conversations — qui en avaient chacun leur version. Ce fichier fige ce que
/// les quatre doivent montrer.
///
/// Lancer avec : flutter test test/apercu_message_test.dart
void main() {
  const jsonContact =
      '{"v":1,"contacts":[{"name":"Jean Dupont","phones":["+237691234567"]}]}';
  const jsonDeuxContacts =
      '{"v":1,"contacts":[{"name":"Jean Dupont","phones":["+1"]},'
      '{"name":"Marie","phones":["+2"]}]}';
  const jsonPosition =
      '{"v":1,"location":{"lat":3.848,"lng":11.502,"label":"Douala"}}';
  const jsonPositionSansNom = '{"v":1,"location":{"lat":3.848,"lng":11.502}}';

  group("Le défaut signalé : plus jamais de JSON brut à l'écran", () {
    test("CONTACT rend le nom, jamais la charge", () {
      final vu = apercuMessage("CONTACT", jsonContact);
      expect(vu, "👤 Jean Dupont");
      expect(vu.contains("{"), isFalse);
      expect(vu.contains("phones"), isFalse);
    });

    test("plusieurs contacts : le premier et le compte des autres", () {
      expect(apercuMessage("CONTACT", jsonDeuxContacts),
          "👤 Jean Dupont et 1 autre");
    });

    test("LOCATION rend le lieu, jamais les coordonnées brutes", () {
      final vu = apercuMessage("LOCATION", jsonPosition);
      expect(vu, "📍 Douala");
      expect(vu.contains("lat"), isFalse);
    });

    test("position sans nom : libellé générique, pas de JSON", () {
      expect(apercuMessage("LOCATION", jsonPositionSansNom),
          "📍 Position partagée");
    });

    test("charge illisible : on dégrade, on n'expose pas", () {
      expect(apercuMessage("CONTACT", "ceci n'est pas du json"), "👤 Contact");
      expect(apercuMessage("LOCATION", "{cassé"), "📍 Position");
    });
  });

  group("Fichiers et documents — l'autre moitié du défaut", () {
    test("document : le NOM du fichier identifie, pas la légende", () {
      expect(
        apercuMessage("FILE", "regarde ça", nomFichier: "contrat.pdf"),
        "📎 contrat.pdf",
      );
    });

    test("fichier sans nom ni légende : libellé, et surtout PAS du vide", () {
      // C'est le cas qui affichait une ligne blanche : `content` vaut `""` et
      // non `null` pour un média sans légende.
      expect(apercuMessage("FILE", ""), "📎 Fichier");
      expect(apercuMessage("FILE", null), "📎 Fichier");
      expect(apercuMessage("FILE", "   "), "📎 Fichier");
    });

    test("fichier sans nom mais avec légende : la légende sert de repli", () {
      expect(apercuMessage("FILE", "le devis"), "📎 le devis");
    });

    test("photo et vidéo : la légende quand il y en a une", () {
      expect(apercuMessage("IMAGE", null), "📷 Photo");
      expect(apercuMessage("IMAGE", "au bureau"), "📷 au bureau");
      expect(apercuMessage("VIDEO", ""), "🎥 Vidéo");
      expect(apercuMessage("VIDEO", "la démo"), "🎥 la démo");
    });

    test("vocal : libellé fixe", () {
      expect(apercuMessage("AUDIO", null), "🎤 Message vocal");
      expect(apercuMessage("AUDIO", "peu importe"), "🎤 Message vocal");
    });
  });

  group("Texte et types inconnus", () {
    test("TEXT rend le texte", () {
      expect(apercuMessage("TEXT", "bonjour"), "bonjour");
    });

    test("les marqueurs de mise en forme sont retirés par l'appelant", () {
      expect(
        apercuMessage("TEXT", "*coucou*",
            nettoyerTexte: (t) => t.replaceAll("*", "")),
        "coucou",
      );
    });

    test("un type inconnu montre son texte plutôt que son nom technique", () {
      // Le serveur a ajouté deux types en août 2026 ; il en ajoutera d'autres.
      expect(apercuMessage("STICKER", "salut"), "salut");
      expect(apercuMessage("STICKER", null), "[STICKER]");
    });
  });
}
