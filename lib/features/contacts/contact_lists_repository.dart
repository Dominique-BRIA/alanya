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
  Future<List<ListeContacts>> list() async {
    final data = await _api.get("/api/contact-lists");
    final brut = data["lists"] as List?;
    if (brut == null) return const [];
    return brut
        .whereType<Map<String, dynamic>>()
        .map(ListeContacts.fromJson)
        .toList();
  }

  /// Crée une liste.
  ///
  /// ⚠️ Rend AUSSI les numéros que le serveur n'a pas su rattacher
  /// (`unknownNumbers`). Les taire ferait croire à un ajout réussi : l'appelant
  /// doit pouvoir dire lesquels n'ont pas été retenus, sinon l'utilisateur
  /// cherchera longtemps pourquoi sa liste compte trois membres au lieu de cinq.
  Future<({ListeContacts liste, List<String> numerosInconnus})> creer({
    required String nom,
    List<String>? membreIds,
    List<String>? numeros,
    String? couleur,
    String? sonnerie,
  }) async {
    final data = await _api.post("/api/contact-lists", {
      "name": nom,
      if (membreIds != null) "memberIds": membreIds,
      if (numeros != null) "memberNumbers": numeros,
      if (couleur != null) "color": couleur,
      if (sonnerie != null) "ringtone": sonnerie,
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
    String? sonnerie,
  }) async {
    final data = await _api.patch("/api/contact-lists/$id", {
      if (nom != null) "name": nom,
      if (membreIds != null) "memberIds": membreIds,
      if (numeros != null) "memberNumbers": numeros,
      if (couleur != null) "color": couleur,
      if (sonnerie != null) "ringtone": sonnerie,
    });
    return _resultat(data);
  }

  /// Supprime une liste. Le serveur rend 204 sans corps.
  Future<void> supprimer(String id) => _api.delete("/api/contact-lists/$id");

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
