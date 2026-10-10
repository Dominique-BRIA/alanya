import 'package:flutter_test/flutter_test.dart';

import 'package:alanya/models/contact.dart';
import 'package:alanya/models/conversation.dart';
import 'package:alanya/models/blocked_user.dart';
import 'package:alanya/models/auth_user.dart';

/// Spécification exécutable d'UNE règle : **quand on montre un numéro à la
/// place d'un nom, il est formaté.**
///
/// Pourquoi ce fichier. Le user a signalé des numéros collés au transfert
/// d'appel et à l'ajout d'une personne dans un appel. Ce n'étaient pas ces deux
/// écrans le problème : le repli `pseudo ?? publicNumber` se décidait dans les
/// getters `displayName` des modèles, donc TOUS les écrans affichaient un
/// numéro brut à la fois, et corriger écran par écran en aurait laissé passer.
///
/// Ces contrôles portent sur les modèles, pas sur les écrans : c'est le seul
/// niveau où la règle est vraie une fois pour toutes.
///
/// Lancer avec : flutter test test/nom_affiche_test.dart
void main() {
  const brut = "123456";
  const formate = "12 34 56";

  group("Sans pseudo, le numéro affiché est FORMATÉ", () {
    test("Contact", () {
      final c = Contact(
        id: "c1",
        alias: null,
        isBlocked: false,
        userId: "u1",
        publicNumber: brut,
        pseudo: null,
        avatarUrl: null,
      );
      expect(c.displayName, formate);
    });

    test("ConvMember (sélecteurs de transfert et d'ajout à un appel)", () {
      final m = ConvMember(id: "u1", pseudo: null, publicNumber: brut);
      expect(m.displayName, formate);
    });

    test("BlockedUser", () {
      final b = BlockedUser(
        idBlock: 1,
        idCallerBlock: "u1",
        publicNumber: brut,
        dateBlock: DateTime(2026, 8, 18),
      );
      expect(b.displayName, formate);
    });
  });

  group("Le pseudo et l'alias restent prioritaires", () {
    test("un pseudo n'est jamais remplacé par le numéro", () {
      final m = ConvMember(id: "u1", pseudo: "Jean", publicNumber: brut);
      expect(m.displayName, "Jean");
    });

    test("l'alias d'un contact prime sur le pseudo", () {
      final c = Contact(
        id: "c1",
        alias: "Papa",
        isBlocked: false,
        userId: "u1",
        publicNumber: brut,
        pseudo: "Jean",
        avatarUrl: null,
      );
      expect(c.displayName, "Papa");
    });
  });

  group("Le formatage suit les autres longueurs", () {
    test("un centre d'appels à 4 chiffres", () {
      final m = ConvMember(id: "u1", pseudo: null, publicNumber: "0000");
      expect(m.displayName, "00 00");
    });

    test("un identifiant à 8 chiffres, le format généré par le serveur", () {
      final m = ConvMember(id: "u1", pseudo: null, publicNumber: "67641599");
      expect(m.displayName, "67 64 15 99");
    });
  });

  group("AuthUser.nomAffiche — le nom qu'on envoie AUX AUTRES", () {
    // 🔴 CE GETTER PART SUR LE RÉSEAU (`bindUser`), et c'est ce qui le rend
    // différent des autres : il ne décide pas ce que JE lis, il décide ce que
    // les autres voient s'afficher chez eux, en appel comme en réunion.
    //
    // Le défaut du 26/08/2026 : il valait `pseudo ?? publicNumber`, et le nom
    // n'était donc jamais consulté. En réunion, chacun voyait le pseudo des
    // autres. La règle du serveur (`src/lib/display-name.mjs`) dit pourtant
    // « nom, puis pseudo, puis numéro » — les deux doivent la dire pareil,
    // sinon une même personne s'appelle autrement selon la porte par laquelle
    // son nom est arrivé.
    AuthUser faire({String? nom, String? pseudo}) => AuthUser(
          id: "u1",
          email: null,
          publicNumber: brut,
          nom: nom,
          pseudo: pseudo,
        );

    test("le nom passe avant le pseudo", () {
      expect(faire(nom: "BRIA Dominique", pseudo: "Domi").nomAffiche,
          "BRIA Dominique");
    });

    test("sans nom, le pseudo prend le relais", () {
      expect(faire(pseudo: "Domi").nomAffiche, "Domi");
    });

    test("un nom vide ne compte pas pour un nom", () {
      // La colonne accepte la chaîne vide, et un `??` seul l'aurait retenue :
      // on se serait présenté sous un nom invisible.
      expect(faire(nom: "   ", pseudo: "Domi").nomAffiche, "Domi");
    });

    test("sans rien, le numéro — et il est FORMATÉ", () {
      expect(faire().nomAffiche, formate);
    });
  });

  group("La recherche continue de fonctionner", () {
    test("le numéro BRUT reste accessible à côté du nom affiché", () {
      // Les trois écrans qui filtrent testent `displayName` ET `publicNumber`.
      // C'est ce second test qui fait que taper « 123456 » trouve encore, alors
      // que le nom affiché vaut désormais « 12 34 56 ».
      final m = ConvMember(id: "u1", pseudo: null, publicNumber: brut);
      expect(m.publicNumber, brut);
      expect(m.publicNumber.contains("123456"), isTrue);
    });
  });
}
