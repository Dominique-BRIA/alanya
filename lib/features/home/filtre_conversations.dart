/// Le filtre actif de la liste des conversations.
///
/// ⚠️ CALQUÉ SUR LE WEB (`app/(protected)/chats/chats.tsx`), y compris dans ses
/// raisons — les deux clients doivent se comporter pareil devant les mêmes
/// listes, sinon « Famille » ne désigne pas le même ensemble d'un écran à
/// l'autre.
///
/// 🔴 **UN SEUL FILTRE ACTIF À LA FOIS**, et non deux états à tenir accordés.
/// Et les listes viennent APRÈS les filtres système, sans jamais s'y mélanger :
/// un filtre système décrit un ÉTAT de la conversation (non lue, groupe), une
/// liste désigne un CERCLE DE PERSONNES que l'utilisateur a lui-même constitué.
/// Les confondre ferait croire que « Famille » est une notion de l'application.
library;

/// Les filtres système, dans l'ordre de la rangée.
///
/// ⚠️ `locked` et `blocked` du web sont volontairement ABSENTS ici : ils
/// reposent sur des données que la liste mobile ne porte pas encore. Les
/// afficher sans pouvoir les honorer serait pire que de ne pas les proposer.
enum FiltreSysteme { tout, nonLues, groupes }

/// Préfixe qui empêche l'identifiant d'une liste — **une chaîne libre venue du
/// serveur** — de se faire passer pour un filtre système.
const String prefixeListe = "liste:";

/// Le filtre actif : soit un filtre système, soit une liste.
class FiltreConversations {
  const FiltreConversations.systeme(this.systeme) : idListe = null;
  const FiltreConversations.liste(String id)
      : systeme = FiltreSysteme.tout,
        idListe = id;

  final FiltreSysteme systeme;

  /// L'identifiant de la liste qui filtre, ou `null` pour un filtre système.
  final String? idListe;

  bool get estUneListe => idListe != null;

  /// La clé stable de ce filtre, préfixée pour une liste.
  String get cle => idListe == null ? systeme.name : "$prefixeListe$idListe";

  @override
  bool operator ==(Object autre) =>
      autre is FiltreConversations &&
      autre.systeme == systeme &&
      autre.idListe == idListe;

  @override
  int get hashCode => Object.hash(systeme, idListe);
}

/// Les identifiants et numéros d'une liste, prêts à comparer.
///
/// ⚠️ Construits UNE FOIS et non reparcourus par conversation : la liste des
/// discussions se refiltre à chaque message reçu, et un parcours par
/// conversation multiplierait le coût par le nombre de membres.
///
/// Les numéros ne sont qu'un SECOND essai, pour une conversation venue d'un
/// cache ancien dont le membre n'aurait pas d'identifiant exploitable. Les deux
/// façons d'alimenter une liste — contact choisi, numéro composé — aboutissent
/// au même compte, donc au même résultat.
class MembresDuFiltre {
  MembresDuFiltre(this.identifiants, this.numeros);

  final Set<String> identifiants;
  final Set<String> numeros;

  static final vide = MembresDuFiltre(const {}, const {});
}

/// Ne garde que les chiffres — un numéro se compare sans ses espaces.
String chiffresSeuls(String brut) => brut.replaceAll(RegExp(r'\D'), '');

/// Cette conversation appartient-elle à la liste active ?
///
/// 🔴 **UN GROUPE N'EST JAMAIS DANS UNE LISTE.** Une liste rassemble des
/// personnes, pas des salons : un groupe qui compterait un membre de la liste
/// n'est pas pour autant une conversation avec ce cercle. C'est la règle du
/// web, et elle doit être la même ici.
///
/// [idsMembres] et [numerosMembres] décrivent les participants de la
/// conversation ; [monId] sert à écarter le porteur du téléphone, comme partout
/// ailleurs — le correspondant, c'est le membre qui n'est pas soi.
bool estDansListe({
  required bool estGroupe,
  required List<({String id, String numero})> membres,
  required String? monId,
  required MembresDuFiltre filtre,
}) {
  if (estGroupe) return false;
  ({String id, String numero})? pair;
  for (final m in membres) {
    if (m.id != monId) {
      pair = m;
      break;
    }
  }
  // Une conversation à un seul participant, c'est « Moi » : mes notes ne sont
  // le cercle de personne.
  if (pair == null) return false;

  if (filtre.identifiants.contains(pair.id.toLowerCase())) return true;
  final numero = chiffresSeuls(pair.numero);
  return numero.isNotEmpty && filtre.numeros.contains(numero);
}
