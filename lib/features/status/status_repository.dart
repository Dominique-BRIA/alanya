import '../../core/authed_api.dart';
import '../../models/status.dart';

class StatusRepository {
  StatusRepository(this._api);
  final AuthedApi _api;

  Future<StatusFeed> feed() async {
    final data = await _api.get("/api/statuses");
    return StatusFeed.fromJson(data);
  }

  /// Publie un statut texte avec couleur de fond (hex #RRGGBB).
  Future<void> createText(String text, String bgColor) async {
    await _api.post("/api/statuses", {
      "type": "TEXT",
      "text": text,
      "bgColor": bgColor,
    });
  }

  /// Publie un statut média (image ou vidéo) via l'ID d'un média déjà uploadé.
  ///
  /// [legende] est le texte posé sous le média, comme la légende d'un statut
  /// WhatsApp. ⚠️ AUCUN CHANGEMENT SERVEUR N'A ÉTÉ NÉCESSAIRE : la colonne
  /// `text` de `statut` existe depuis toujours, et `createStatusSchema`
  /// n'exigeait `text` que pour un statut TEXTE, sans jamais l'interdire aux
  /// autres. Elle n'était simplement jamais remplie ni affichée.
  Future<void> createMedia(String mediaId, String type,
      {String? legende}) async {
    await _api.post("/api/statuses", {
      "type": type,
      "mediaId": mediaId,
      if (legende != null && legende.isNotEmpty) "text": legende,
    });
  }

  Future<void> markViewed(String statusId) async {
    await _api.post("/api/statuses/$statusId/view", {});
  }

  /// Liste des personnes ayant vu mon statut ({userId, name, avatarUrl, viewedAt}).
  Future<List<Map<String, dynamic>>> getViews(String statusId) async {
    final data = await _api.get("/api/statuses/$statusId/views");
    return ((data["views"] as List?) ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<void> delete(String statusId) async {
    await _api.delete("/api/statuses/$statusId");
  }

  /// Mon audience : qui a le droit de voir mes statuts.
  ///
  /// La LISTE se lit différemment selon le mode — exclusion en
  /// `MES_CONTACTS_SAUF`, inclusion en `PARTAGER_AVEC`, ignorée en
  /// `MES_CONTACTS`. C'est la même table côté serveur, et c'est ce qui permet
  /// de changer de mode sans perdre les personnes déjà désignées.
  Future<AudienceStatuts> audience() async {
    final data = await _api.get("/api/statuses/privacy");
    return AudienceStatuts.fromJson(data);
  }

  /// Remplace le mode ET la liste d'un bloc.
  ///
  /// PUT et non PATCH : l'écran envoie l'état complet, jamais un delta — c'est
  /// ce qui rend l'enregistrement rejouable sans effet de bord.
  Future<void> setAudience(String mode, List<String> userIds) async {
    await _api.put("/api/statuses/privacy", {
      "mode": mode,
      "userIds": userIds,
    });
  }
}

/// Les trois audiences possibles, telles que le serveur les nomme.
///
/// ⚠️ CES TROIS CHAÎNES SONT UN CONTRAT : elles doivent rester identiques à
/// l'enum PostgreSQL `StatusAudienceMode`, au schéma de validation Zod et à
/// `src/lib/statut-audience.mjs`. Une faute de frappe ici passerait la
/// compilation et se verrait seulement en production.
abstract final class ModeAudience {
  static const mesContacts = "MES_CONTACTS";
  static const mesContactsSauf = "MES_CONTACTS_SAUF";
  static const partagerAvec = "PARTAGER_AVEC";

  static const tous = [mesContacts, mesContactsSauf, partagerAvec];

  /// Un mode inconnu retombe sur le plus restreint des comportements sensés —
  /// jamais sur une audience plus large. Même règle que le serveur.
  static String valide(String? mode) =>
      tous.contains(mode) ? mode! : mesContacts;
}

class AudienceStatuts {
  const AudienceStatuts({required this.mode, required this.userIds});

  final String mode;

  /// Les personnes nommées, par identifiant de compte.
  final List<String> userIds;

  factory AudienceStatuts.fromJson(Map<String, dynamic> j) => AudienceStatuts(
        mode: ModeAudience.valide(j["mode"] as String?),
        userIds: ((j["users"] as List?) ?? [])
            .map((u) => (u as Map)["userId"] as String)
            .toList(),
      );
}
