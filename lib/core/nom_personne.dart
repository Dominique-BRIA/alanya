/// UN NOM DE PERSONNE A DE VRAIES LETTRES (13/11/2026, demande du user).
///
/// « 2 caractères minimum » laissait passer « .. », « -- » ou deux caractères
/// INVISIBLES (espace sans largeur, remplissage coréen « ㅤ », espace
/// braille…), que `trim()` ne retire pas : le compte s'affichait sans nom.
///
/// ⚠️ JUMEAU DU SERVEUR : `nettoyerNom` et `nomPersonneValide` dans
/// `banc-backend-alanya/src/lib/validation.ts`. Le serveur fait foi ; cet écho
/// sert à refuser dans le formulaire, avant l'envoi.
library;

final _invisibles = RegExp(
    r'[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180F\u200B-\u200F\u202A-\u202E\u2060-\u206F\u2800\u3164\uFEFF\uFFA0]',
    unicode: true);
final _espaces = RegExp(r'\s+', unicode: true);
final _lettreOuChiffre = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Invisibles retirés, espaces regroupés, bords coupés.
String nettoyerNom(String brut) =>
    brut.replaceAll(_invisibles, '').replaceAll(_espaces, ' ').trim();

/// Au moins deux lettres ou chiffres, de n'importe quelle écriture.
bool nomPersonneValide(String nom) =>
    _lettreOuChiffre.allMatches(nettoyerNom(nom)).length >= 2;
