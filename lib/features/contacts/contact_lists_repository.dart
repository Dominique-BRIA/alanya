import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/authed_api.dart';
import '../../models/contact_list.dart';

/// Accès aux listes de contacts personnalisées.
///
/// ⚠️ Le contrat vit côté serveur (`src/lib/contact-lists.ts`). Ce dépôt ne fait
/// que le traduire en Dart, il n'ajoute aucune règle.
class ContactListsRepository {
  ContactListsRepository(this._api);
  final AuthedApi _api;

  /// Toutes mes listes, avec leurs membres.
  ///
  /// La réponse est gardée sur l'appareil ([enCache]) : sans réseau, les
  /// listes restent visibles (18/11/2026).
  Future<List<ListeContacts>> list() async {
    final data = await _api.get("/api/contact-lists");
    final brut = data["lists"] as List?;
    if (brut == null) return const [];
    try {
      await (await SharedPreferences.getInstance()).setString(_cleCache, jsonEncode(brut));
    } catch (_) {
      // Un cache raté ne doit pas faire échouer la lecture.
    }
    return _lire(brut);
  }

  /*
   * 🐛 « LES LISTES DE CONTACTS NE SONT PAS VISIBLES SANS CONNEXION » (user,
   * 18/11/2026). Elles ne vivaient qu'en mémoire, rechargées au serveur à
   * chaque ouverture : hors ligne, la rangée de l'écran Discussions restait
   * vide, comme l'écran des listes. La dernière réponse du serveur est donc
   * gardée ici, et relue quand il ne répond pas.
   *
   * ⚠️ EFFACÉE À LA DÉCONNEXION ([oublierCache]) : les listes d'un compte ne
   * doivent pas apparaître au compte suivant sur le même téléphone.
   */
  static const _cleCache = 'listes_contacts_cache';

  /// Les listes gardées sur l'appareil ; vide si rien n'a encore été lu.
  static Future<List<ListeContacts>> enCache() async {
    try {
      final brut = (await SharedPreferences.getInstance()).getString(_cleCache);
      if (brut == null) return const [];
      return _lire(jsonDecode(brut) as List);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> oublierCache() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_cleCache);
    } catch (_) {}
  }

  static List<ListeContacts> _lire(List brut) => brut
      .whereType<Map>()
      .map((m) => ListeContacts.fromJson(Map<String, dynamic>.from(m)))
      .toList();

  /// Crée une liste.
  ///
  /// ⚠️ Rend AUSSI les numéros que le serveur n'a pas su rattacher
  /// (`unknownNumbers`). Les taire ferait croire à un ajout réussi : l'appelant
  /// doit pouvoir dire lesquels n'ont pas été retenus, sinon l'utilisateur
  /// cherchera longtemps pourquoi sa liste compte trois membres au lieu de cinq.
  /// ⚠️ [sonnerie] DISTINGUE « ne pas toucher » de « retirer ».
  ///
  /// Laisser le paramètre absent ne change rien ; passer `(url: null)` envoie un
  /// `null` explicite, que le serveur accepte pour REVENIR à la sonnerie par
  /// défaut. Sans cette distinction — un simple `String?` — choisir « Par
  /// défaut » aurait été indiscernable de « ne rien changer », et la sonnerie
  /// n'aurait jamais pu être retirée.
  Future<({ListeContacts liste, List<String> numerosInconnus})> creer({
    required String nom,
    List<String>? membreIds,
    List<String>? numeros,
    String? couleur,
    ({String? url})? sonnerie,
    // Le son des MESSAGES, distinct de la sonnerie d appel. Meme convention :
    // le record present avec `url: null` retire le son, absent le laisse.
    ({String? url})? sonnerieMessage,
  }) async {
    final data = await _api.post("/api/contact-lists", {
      "name": nom,
      if (membreIds != null) "memberIds": membreIds,
      if (numeros != null) "memberNumbers": numeros,
      if (couleur != null) "color": couleur,
      if (sonnerie != null) "ringtone": sonnerie.url,
      if (sonnerieMessage != null) "ringtoneMessage": sonnerieMessage.url,
    });
    return _resultat(data);
  }

  /// Met à jour une liste.
  ///
  /// ⚠️ Fournir `membreIds` REMPLACE l'ensemble des membres, il n'ajoute pas —
  /// c'est le contrat du serveur, et il rend l'appel idempotent. L'appelant doit
  /// donc envoyer la liste complète voulue, jamais un delta.
  Future<({ListeContacts liste, List<String> numerosInconnus})> modifier(
    String id, {
    String? nom,
    List<String>? membreIds,
    List<String>? numeros,
    String? couleur,
    ({String? url})? sonnerie,
    // Le son des MESSAGES, distinct de la sonnerie d appel. Meme convention :
    // le record present avec `url: null` retire le son, absent le laisse.
    ({String? url})? sonnerieMessage,
  }) async {
    final data = await _api.patch("/api/contact-lists/$id", {
      if (nom != null) "name": nom,
      if (membreIds != null) "memberIds": membreIds,
      if (numeros != null) "memberNumbers": numeros,
      if (couleur != null) "color": couleur,
      // Voir `creer` : le record présent avec `url: null` retire la sonnerie.
      if (sonnerie != null) "ringtone": sonnerie.url,
      // 🔴 CE CHAMP MANQUAIT, et c'est par ici que passe TOUT changement de son
      // d'une liste existante — l'écran des sonneries n'appelle jamais `creer`.
      // Le paramètre était déclaré et documenté, le corps de la requête ne le
      // portait pas : le serveur ne recevait rien, gardait `NULL`, et le son
      // par défaut continuait de sonner sans qu'aucune erreur ne s'affiche.
      // L'écran, lui, réaffichait le choix depuis son propre état : tout avait
      // l'air enregistré jusqu'au rechargement de l'application.
      if (sonnerieMessage != null) "ringtoneMessage": sonnerieMessage.url,
    });
    return _resultat(data);
  }

  /// Supprime une liste. Le serveur rend 204 sans corps.
  Future<void> supprimer(String id) => _api.delete("/api/contact-lists/$id");

  /// Enregistre l'ORDRE DE PRIORITÉ des listes, et rend la liste réordonnée.
  ///
  /// 🔴 CET ORDRE DÉCIDE QUELLE SONNERIE GAGNE quand quelqu'un appartient à
  /// plusieurs listes. La règle était « la plus anciennement créée » : stable,
  /// mais le choix de personne.
  ///
  /// ⚠️ TOUTES LES LISTES DOIVENT ÊTRE CITÉES, exactement une fois — le serveur
  /// refuse un sous-ensemble (422 `ORDRE_INCOMPLET`). N'envoyer que celles qu'on
  /// a bougées obligerait le serveur à inventer une règle pour les autres.
  ///
  /// ⚠️ ON REPREND CE QUE LE SERVEUR REND, jamais l'ordre qu'on croit avoir
  /// envoyé : les deux divergent dès qu'un second appareil écrit en même temps.
  Future<List<ListeContacts>> reordonner(List<String> ids) async {
    final data = await _api.put("/api/contact-lists/ordre", {"ids": ids});
    final brut = data["lists"] as List? ?? const [];
    return brut
        .whereType<Map<String, dynamic>>()
        .map(ListeContacts.fromJson)
        .toList();
  }

  ({ListeContacts liste, List<String> numerosInconnus}) _resultat(
      Map<String, dynamic> data) {
    final liste = ListeContacts.fromJson(
        data["list"] as Map<String, dynamic>? ?? const {});
    final inconnus =
        (data["unknownNumbers"] as List?)?.map((n) => n.toString()).toList() ??
            const <String>[];
    return (liste: liste, numerosInconnus: inconnus);
  }
}
