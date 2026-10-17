/// Numéros de téléphone : normalisation et présentation, selon le pays.
///
/// ⚠️ **MIROIR EXACT de `backend-alanya/src/lib/telephone.mjs`**, et du miroir
/// web `STAGE-WEB/src/services/telephone.ts`. La règle est décidée côté
/// SERVEUR — c'est lui qui normalise ce qui va en base, et lui seul fait foi.
/// Toute évolution se fait là-bas d'abord.
///
/// POURQUOI ELLE EXISTE : `users.mobile` est UNIQUE, et la base portait déjà
/// deux formes du même numéro — « 657308298 » et « +237657308299 », constatées
/// le 25/08/2026. Deux formes ne se ressemblent pas pour PostgreSQL : la même
/// personne peut s'inscrire deux fois, et la recherche par numéro n'en trouve
/// qu'une.
library;

/// Groupement des chiffres à l'affichage, par code ISO 3166-1 alpha-2.
///
/// ⚠️ CE N'EST QUE DE LA PRÉSENTATION. Rien de ce qui est envoyé au serveur
/// n'en dépend : [normaliserTelephone] produit toujours la même chaîne, quels
/// que soient les espaces affichés.
const Map<String, List<int>> _groupes = {
  // Amérique du Nord : 3-3-4, universellement lu ainsi.
  "US": [3, 3, 4],
  "CA": [3, 3, 4],
  // Royaume-Uni : 4-6 sur les mobiles (07xxx xxxxxx).
  "GB": [4, 6],
};

/// Par défaut : des paires. « 6 91 23 45 67 » se lit sans effort.
const int _groupeDefaut = 2;

String _chiffres(String? valeur) =>
    (valeur ?? "").replaceAll(RegExp(r"\D"), "");

/// La forme CANONIQUE : `+` suivi de l'indicatif et du numéro national, sans
/// séparateur. C'est celle qui part au serveur.
///
/// Absorbe les trois façons de saisir le même numéro :
///   - national, tel qu'on le dicte      : « 6 91 23 45 67 »
///   - national avec le zéro de service  : « 06 91 23 45 67 »
///   - international, déjà complet       : « +237 691 23 45 67 » ou « 00237… »
///
/// ⚠️ LE ZÉRO INITIAL EST RETIRÉ : c'est un préfixe d'acheminement INTERNE au
/// pays, il n'a aucun sens derrière un indicatif — « +33 0 6 … » n'appelle
/// personne.
///
/// ⚠️ L'INDICATIF N'EST RETIRÉ QU'UNE FOIS. Le retirer en boucle mutilerait un
/// numéro national commençant par les chiffres de son propre indicatif, qu'on
/// ne peut pas distinguer d'un doublon.
String normaliserTelephone(String saisie, String prefixePays) {
  var n = _chiffres(saisie);
  if (n.isEmpty) return "";

  /// 🔴 UN « + » EN TÊTE DIT « CE NUMÉRO EST DÉJÀ COMPLET » — on n'y ajoute
  /// rien.
  ///
  /// Sans cette sortie, l'indicatif du compte se collait devant un numéro
  /// étranger : « +221 34543678 » sur un compte déclaré en France ressortait
  /// « +3322134543678 », injoignable — et `users.mobile` est UNIQUE.
  ///
  /// Le cas est fréquent et légitime : on vit dans un pays et on garde une
  /// ligne d'un autre. C'est la raison même pour laquelle changer de pays ne
  /// touche pas au numéro.
  ///
  /// ⚠️ Le test porte sur la SAISIE BRUTE : `_chiffres` a déjà retiré le « + ».
  if (saisie.trim().startsWith("+")) return "+$n";

  final indicatif = _chiffres(prefixePays);

  // « 00 » international : la forme longue de « + ».
  if (n.startsWith("00")) n = n.substring(2);

  if (indicatif.isNotEmpty && n.startsWith(indicatif)) {
    n = n.substring(indicatif.length);
  }

  n = n.replaceFirst(RegExp(r"^0+"), "");

  if (n.isEmpty) return "";
  return indicatif.isEmpty ? "+$n" : "+$indicatif$n";
}

/// Le numéro tel qu'on le LIT : « +237 6 91 23 45 67 ».
String formaterTelephone(String saisie, String prefixePays, [String? iso2]) {
  final canonique = normaliserTelephone(saisie, prefixePays);
  if (canonique.isEmpty) return "";

  final indicatif = _chiffres(prefixePays);

  // 🔴 LE NUMÉRO NE PORTE PAS L'INDICATIF DEMANDÉ : on le rend tel quel.
  //
  // Le découpage suppose que `canonique` commence par `indicatif` pour savoir
  // où finit l'indicatif. Sinon la soustraction de longueurs mange des chiffres
  // et en réattribue d'autres : « +33612345678 » présenté avec « +237 »
  // ressortait « +237 12 34 56 78 » — un AUTRE numéro, pas une mise en forme.
  //
  // Constaté le 26/08/2026 en ajoutant le choix du pays de la ligne dans les
  // réglages : changer ce sélecteur réécrivait le numéro déjà saisi.
  if (indicatif.isNotEmpty && !canonique.startsWith("+$indicatif")) {
    return canonique;
  }

  final national = canonique.substring(1 + indicatif.length);
  if (national.isEmpty) return "+$indicatif";

  final decoupe = _groupes[(iso2 ?? "").toUpperCase()];
  final morceaux = <String>[];

  if (decoupe != null) {
    var reste = national;
    for (final taille in decoupe) {
      if (reste.isEmpty) break;
      morceaux.add(reste.substring(0, taille.clamp(0, reste.length)));
      reste = reste.length > taille ? reste.substring(taille) : "";
    }
    // Ce qui dépasse le découpage annoncé est conservé, jamais coupé : un
    // numéro plus long qu'attendu reste un numéro.
    if (reste.isNotEmpty) morceaux.add(reste);
  } else {
    // Paires, EN PARTANT DE LA FIN. Les numéros d'Afrique francophone comptent
    // 9 chiffres, un nombre IMPAIR : grouper depuis le début laisserait un
    // chiffre orphelin à la fin, alors que l'usage local isole le premier —
    // « 6 91 23 45 67 », qui est la façon dont ces numéros se dictent.
    var reste = national;
    while (reste.length > _groupeDefaut) {
      morceaux.insert(0, reste.substring(reste.length - _groupeDefaut));
      reste = reste.substring(0, reste.length - _groupeDefaut);
    }
    if (reste.isNotEmpty) morceaux.insert(0, reste);
  }

  return "+$indicatif ${morceaux.join(" ")}";
}
