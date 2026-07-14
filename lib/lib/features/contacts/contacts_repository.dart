import '../../core/api_client.dart';
import '../../core/authed_api.dart';
import '../../models/contact.dart';

class ContactsRepository {
  ContactsRepository(this._api);
  final AuthedApi _api;

  /// Recherche un utilisateur par son numéro Alanya à 6 chiffres.
  Future<UserSearchResult> searchByNumber(String number) async {
    final data = await _api.get("/api/users/search?number=$number");
    return UserSearchResult.fromJson(data);
  }

  /// Envoie un tableau de numéros à 6 chiffres et renvoie ceux qui sont sur Alanya.
  /// Utilisé pour la synchronisation automatique du répertoire téléphonique.
  Future<List<UserSearchResult>> matchNumbers(List<String> numbers) async {
    if (numbers.isEmpty) return [];
    final data = await _api.post("/api/users/match", {"numbers": numbers});
    final raw = data["matched"] as List?;
    if (raw == null) return [];
    return raw
        .map((u) => UserSearchResult.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  /// Charge la liste des contacts du répertoire.
  Future<List<Contact>> list() async {
    final data = await _api.get("/api/contacts");
    final raw = data["contacts"];
    if (raw == null) return [];
    return (raw as List)
        .map((c) => Contact.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Ajoute un contact via son numéro Alanya à 6 chiffres.
  Future<Contact> add(String publicNumber, {String? alias}) async {
    final data = await _api.post("/api/contacts", {
      "publicNumber": publicNumber,
      if (alias != null && alias.isNotEmpty) "alias": alias,
    });
    return Contact.fromJson(data);
  }

  /// Ajoute plusieurs contacts en une seule passe (import répertoire téléphonique).
  /// Ignore silencieusement les doublons (code ALREADY_CONTACT).
  Future<int> addMany(List<({String publicNumber, String? alias})> entries) async {
    int added = 0;
    for (final e in entries) {
      try {
        await add(e.publicNumber, alias: e.alias);
        added++;
      } on ApiException catch (ex) {
        if (ex.code == "ALREADY_CONTACT") continue; // déjà présent, on ignore
        rethrow;
      }
    }
    return added;
  }

  Future<void> setBlocked(String contactId, bool blocked) async {
    await _api.patch("/api/contacts/$contactId", {"isBlocked": blocked});
  }

  Future<void> setAlias(String contactId, String alias) async {
    await _api.patch("/api/contacts/$contactId", {"alias": alias});
  }

  Future<void> remove(String contactId) async {
    await _api.delete("/api/contacts/$contactId");
  }
}
