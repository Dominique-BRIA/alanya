/// Normalisation de texte pour TRIER et CHERCHER.
///
/// ⚠️ Sans dépendance : ce fichier s'exécute donc directement sous
/// `flutter test`, et ses règles se vérifient contre des valeurs.
///
/// 🔴 POURQUOI LES ACCENTS COMPTENT ICI. Dart compare les chaînes par point de
/// code : « É » vaut 201 et « Z » vaut 90, donc un tri naïf place **Émile après
/// Zoé**. Et une recherche naïve ne trouve pas « Émile » quand on tape
/// « emile », ce que fait pourtant tout le monde sur un clavier de téléphone.
/// Les deux problèmes ont la même cause, donc la même correction — d'où un seul
/// helper partagé plutôt qu'un pour le tri et un pour le filtre, qui auraient
/// fini par diverger.
library;

/// Table des caractères accentués courants du français, plus quelques voisins
/// (espagnol, portugais) qu'un carnet d'adresses réel contient toujours.
///
/// Une table explicite plutôt qu'une normalisation Unicode : Dart n'expose pas
/// NFD dans la bibliothèque standard, et y ajouter un paquet pour retirer des
/// accents serait disproportionné.
const Map<String, String> _equivalents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Minuscules, sans accents, sans espaces superflus.
///
/// Sert de CLÉ DE TRI et de clé de RECHERCHE. Les deux doivent normaliser de la
/// même façon, sinon un contact trouvable ne serait pas à sa place dans la
/// liste, ou l'inverse.
String normaliseTexte(String brut) {
  final minuscules = brut.toLowerCase().trim();
  final tampon = StringBuffer();
  for (final caractere in minuscules.split('')) {
    tampon.write(_equivalents[caractere] ?? caractere);
  }
  return tampon.toString();
}

/// Compare deux libellés pour un classement alphabétique lisible par un humain.
///
/// ⚠️ Départage par la valeur BRUTE quand les clés normalisées sont égales :
/// sans cela, « Emile » et « Émile » se retrouveraient dans un ordre qui change
/// d'un chargement à l'autre, et deux contacts homonymes sauteraient de place
/// dans la liste à chaque rafraîchissement.
int comparePourTri(String a, String b) {
  final parNormalise = normaliseTexte(a).compareTo(normaliseTexte(b));
  if (parNormalise != 0) return parNormalise;
  return a.compareTo(b);
}

/// [aiguille] apparaît-elle dans [meule], accents et casse ignorés ?
bool contientRecherche(String meule, String aiguille) {
  final q = normaliseTexte(aiguille);
  if (q.isEmpty) return true;
  return normaliseTexte(meule).contains(q);
}
