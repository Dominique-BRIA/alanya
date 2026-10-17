import 'package:flutter/foundation.dart';

import '../features/contacts/contact_lists_repository.dart';
import '../models/contact_list.dart';
import 'api_client.dart';
import 'sonneries_livrees.dart';
import 'token_storage.dart';

/// Ne garde que les chiffres — un numéro se compare sans ses espaces.
String _chiffres(String brut) => brut.replaceAll(RegExp(r'\D'), '');

/// Quelle sonnerie jouer pour un appelant, d'après ses listes de contacts.
///
/// 🔴 CE MAILLON MANQUAIT. La liste stockait bien son `ringtone`, l'écran
/// laissait bien le choisir, et le serveur le rendait — mais **personne ne le
/// lisait à l'arrivée d'un appel** : `startIncoming()` jouait l'asset embarqué,
/// sans condition. La fonctionnalité était complète de bout en bout sauf sur le
/// seul geste qui la rend visible.
///
/// ⚠️ **UN APPEL NE DOIT JAMAIS ATTENDRE LE RÉSEAU POUR SONNER.** Les listes
/// sont donc tenues EN MÉMOIRE et alimentées par les écrans qui les chargent
/// déjà ; si elles ne sont pas encore là, on rend `null` et l'appel sonne avec
/// la sonnerie par défaut. Mieux vaut la mauvaise sonnerie que le silence.
///
/// 🔴 **C'EST AUSSI LA SOURCE UNIQUE DE LA RANGÉE DE FILTRES** (19/08/2026).
/// L'écran des conversations en gardait sa PROPRE copie, chargée une seule fois
/// dans son `initState` : créer ou renommer une liste depuis le carnet ne se
/// voyait qu'au redémarrage de l'application. Deux copies de la même donnée, et
/// une seule des deux se rafraîchissait. En faire un `ChangeNotifier` supprime
/// la classe de problème : qui modifie une liste appelle [alimenter], et tout ce
/// qui l'affiche se remet à jour.
class SonneriesDeListes extends ChangeNotifier {
  SonneriesDeListes(this._depot, this._api, this._jetons);

  final ContactListsRepository _depot;
  final ApiClient _api;
  final TokenStorage _jetons;

  List<ListeContacts> _cache = const [];
  bool _chargementLance = false;

  /// Les listes connues. Jamais nulle : vide tant que rien n'est chargé.
  List<ListeContacts> get listes => _cache;

  /// Alimente le cache depuis un écran qui vient de charger les listes.
  ///
  /// Passer par là plutôt que de refaire l'appel évite une seconde requête pour
  /// la même donnée, et garde le cache frais à chaque création ou modification
  /// de liste — les écrans concernés appellent cette méthode.
  void alimenter(List<ListeContacts> listes) {
    _cache = listes;
    _chargementLance = true;
    notifyListeners();
  }

  /// Recharge depuis le serveur. Rend `false` en cas d'échec, sans lever.
  Future<bool> rafraichir() async {
    try {
      alimenter(await _depot.list());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Charge les listes une fois, en tâche de fond, sans jamais lever.
  ///
  /// Sert le cas où un appel arrive avant que le moindre écran n'ait chargé les
  /// listes : ce premier appel sonnera par défaut, les suivants seront justes.
  Future<void> prechargerSiBesoin() async {
    if (_chargementLance) return;
    _chargementLance = true;
    try {
      alimenter(await _depot.list());
    } catch (_) {
      // Silencieux : une sonnerie personnalisée est un confort, jamais un dû.
      _chargementLance = false;
    }
  }

  /// L'ORDRE DE PRIORITÉ DU COMPTE — transposition exacte d'`ORDRE_LISTES`
  /// côté serveur : `ordre ASC NULLS LAST, createdAt ASC, id ASC`.
  ///
  /// 🔴 CE TRI REMPLACE UN TRI ALPHABÉTIQUE, et c'était toute la panne de
  /// l'écran de réordonnancement : on pouvait glisser les listes dans l'ordre
  /// voulu, le rang partait bien au serveur et revenait bien dans le modèle,
  /// mais l'arbitrage retriait tout par NOM et redésignait donc toujours la
  /// même gagnante. Rien à l'écran ne pouvait l'expliquer. Le web a reçu
  /// exactement ce correctif le 12/09 (`74dc35d`, `parPriorite`).
  ///
  /// ⚠️ LES NON-ORDONNÉES TOMBENT EN DERNIER, jamais en tête — même piège que
  /// `NULLS LAST` en SQL. Une liste sans rang doit céder le pas à celles que
  /// l'utilisateur a explicitement placées, pas les devancer.
  ///
  /// ⚠️ Tant que personne n'a rien ordonné, `ordre` vaut `null` partout et ce
  /// tri se réduit EXACTEMENT à l'ancienneté d'avant : le changement est
  /// invisible jusqu'au premier réordonnancement.
  ///
  /// ⚠️ Le départage final se fait sur `id` et NON sur le nom : renommer une
  /// liste ne doit pas déplacer la sonnerie de quelqu'un.
  static int comparePriorite(ListeContacts a, ListeContacts b) {
    final ra = a.ordre;
    final rb = b.ordre;
    if (ra != rb) {
      if (ra == null) return 1;
      if (rb == null) return -1;
      return ra.compareTo(rb);
    }
    final parAge = a.createdAt.compareTo(b.createdAt);
    return parAge != 0 ? parAge : a.id.compareTo(b.id);
  }

  /// La liste qui décide pour cette personne, parmi celles qui portent un son.
  ///
  /// ⚠️ **Une personne peut appartenir à PLUSIEURS listes.** Il faut donc une
  /// règle, et elle doit être stable : sans elle, la sonnerie changerait d'une
  /// fois à l'autre au gré de l'ordre rendu par le serveur. C'est l'ordre de
  /// priorité choisi par l'utilisateur qui tranche — voir [comparePriorite].
  ///
  /// [son] désigne le champ à consulter : la sonnerie d'APPEL ou celle des
  /// MESSAGES. Les deux partagent tout le reste — l'appartenance, le
  /// rapprochement par numéro, l'arbitrage — et c'est pour cela qu'ils vivent
  /// dans la même fonction : deux copies auraient fini par diverger, et le
  /// dépôt paie déjà régulièrement ce défaut.
  ListeContacts? _listePour(
    String? Function(ListeContacts) son, {
    String? personneId,
    String? numero,
  }) {
    final id = personneId?.toLowerCase();
    final num = numero == null ? "" : _chiffres(numero);
    final candidates =
        _cache
            .where((l) {
              final v = son(l);
              return v != null && v.isNotEmpty;
            })
            .where(
              (l) => l.members.any((m) {
                if (id != null && m.id.toLowerCase() == id) return true;
                return num.isNotEmpty && _chiffres(m.publicNumber) == num;
              }),
            )
            .toList()
          ..sort(comparePriorite);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// La liste qui décide de la sonnerie d'APPEL pour cet appelant, ou `null`.
  ListeContacts? listePourAppelant({String? callerId, String? numero}) =>
      _listePour((l) => l.ringtone, personneId: callerId, numero: numero);

  /// La liste qui décide du son des MESSAGES pour cet expéditeur, ou `null`.
  ListeContacts? listePourExpediteur({String? expediteurId, String? numero}) =>
      _listePour(
        (l) => l.ringtoneMessage,
        personneId: expediteurId,
        numero: numero,
      );

  /// Ce qu'il faut jouer pour cet appelant, ou `null` pour la sonnerie défaut.
  ///
  /// La mise en forme de la valeur — fichier livré, URL importée — vit dans
  /// [_resoudre], partagée avec le son des messages.
  Future<SonnerieAJouer?> sonneriePourAppelant({
    String? callerId,
    String? numero,
  }) => _resoudre(
    listePourAppelant(callerId: callerId, numero: numero)?.ringtone,
  );

  /// Ce qu'il faut jouer à l'arrivée d'un MESSAGE de cette personne, ou `null`
  /// pour le son par défaut.
  ///
  /// 🔴 CE MAILLON MANQUAIT AUSSI — exactement le défaut déjà corrigé pour les
  /// appels, et décrit en tête de ce fichier. La colonne existait, l'écran
  /// laissait choisir, le serveur rendait la valeur : **personne ne la lisait à
  /// l'arrivée d'un message.** `playMessageReceived()` jouait l'asset embarqué,
  /// sans condition.
  ///
  /// ⚠️ Même règle de repli que pour un appel : une forme inconnue ou un jeton
  /// absent rendent `null`, et le son par défaut se fait entendre. Un message
  /// silencieux serait pire qu'un message au mauvais son.
  Future<SonnerieAJouer?> sonneriePourExpediteur({
    String? expediteurId,
    String? numero,
  }) => _resoudre(
    listePourExpediteur(
      expediteurId: expediteurId,
      numero: numero,
    )?.ringtoneMessage,
  );

  /// Rend jouable la valeur brute d'un champ de sonnerie, ou `null`.
  ///
  /// 🔴 DEUX FORMES, ET C'EST TOUT LE SUJET. Le champ porte soit une URL de
  /// média importé, soit le NOM D'UN FICHIER LIVRÉ avec l'application — ce
  /// qu'utilisent les quatre listes créées d'office.
  ///
  /// Cette résolution ne connaissait que la première : elle collait l'adresse
  /// de l'API devant la valeur, quelle qu'elle soit. « liste-bureau.mp3 »
  /// devenait `https://…comliste-bureau.mp3`, sans même la barre oblique. Les
  /// sonneries livrées ne pouvaient donc pas sonner sur Android.
  ///
  /// ⚠️ Une forme INCONNUE rend `null` plutôt qu'une URL construite au hasard :
  /// mieux vaut le son par défaut, qui s'entend, qu'un silence.
  ///
  /// ⚠️ Le catalogue importé rend une URL RELATIVE (`/api/media/<id>`) et la
  /// route des médias exige un jeton, que le lecteur audio ne sait pas joindre
  /// en en-tête. Il passe donc en paramètre, comme partout ailleurs.
  Future<SonnerieAJouer?> _resoudre(String? brut) async {
    if (brut == null || brut.isEmpty) return null;

    // Sonnerie livrée : aucun réseau, aucun jeton, elle est dans le paquet.
    final asset = assetDeSonnerie(brut);
    if (asset != null) return SonnerieAJouer.livree(asset);

    if (brut.startsWith("http://") || brut.startsWith("https://")) {
      return SonnerieAJouer.distante(brut);
    }
    // Seule la forme absolue `/api/media/<id>` se complète en URL. Tout le
    // reste est inconnu, et le silence serait la pire des réponses.
    if (!brut.startsWith("/")) return null;

    final jeton = await _jetons.accessToken;
    if (jeton == null || jeton.isEmpty) return null;
    return SonnerieAJouer.distante("${_api.baseUrl}$brut?token=$jeton");
  }
}

/// Ce qu'il faut jouer, et d'où : du paquet de l'application, ou du réseau.
///
/// Deux natures qu'on ne peut pas confondre — l'une se joue instantanément,
/// l'autre demande un téléchargement et peut échouer.
class SonnerieAJouer {
  const SonnerieAJouer.livree(this.valeur) : estLivree = true;
  const SonnerieAJouer.distante(this.valeur) : estLivree = false;

  /// Vrai : [valeur] est un chemin d'asset. Faux : c'est une URL complète.
  final bool estLivree;
  final String valeur;
}
