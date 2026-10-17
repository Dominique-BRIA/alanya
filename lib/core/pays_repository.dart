import 'api_client.dart';

/// Un pays de la table de référence du serveur.
class Pays {
  final int idPays;
  final String libelle;
  final String? iso2;

  /// Indicatif téléphonique, « +237 ». Peut être vide — la colonne a `""` pour
  /// défaut et certaines lignes anciennes n'en portent pas.
  final String prefix;

  const Pays({
    required this.idPays,
    required this.libelle,
    required this.iso2,
    required this.prefix,
  });

  factory Pays.fromJson(Map<String, dynamic> j) => Pays(
        idPays: (j["idPays"] as num).toInt(),
        libelle: j["libelle"] as String? ?? "",
        iso2: j["iso2"] as String?,
        prefix: j["prefix"] as String? ?? "",
      );

  /// Le drapeau, dérivé du code ISO plutôt que stocké.
  ///
  /// Les 26 lettres A–Z ont un équivalent « indicateur régional » en Unicode
  /// (U+1F1E6…U+1F1FF) : deux d'entre eux accolés forment le drapeau du pays.
  /// « CM » donne donc 🇨🇲 sans qu'aucun drapeau ne soit stocké nulle part, et
  /// un pays ajouté en base apparaît avec le sien sans toucher à l'application.
  String get drapeau {
    final code = (iso2 ?? "").toUpperCase();
    if (code.length != 2) return "";
    const base = 0x1F1E6; // 🇦
    final a = code.codeUnitAt(0), b = code.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return "";
    return String.fromCharCodes([base + (a - 65), base + (b - 65)]);
  }
}

/// Accès à la table de référence des pays.
///
/// 🔴 CE DÉPÔT REMPLACE UNE LISTE CODÉE EN DUR, ET C'EST UN CORRECTIF.
///
/// L'écran d'inscription portait ses 25 pays en dur, avec des identifiants
/// inventés : il disait « 1 = Cameroun » quand la table dit « 1 = Afrique du
/// Sud ». Chaque compte créé depuis le mobile enregistrait donc un pays faux —
/// 4 comptes en Afrique du Sud en production au 25/08/2026, tous censés être
/// au Cameroun. Le serveur ne pouvait rien détecter : l'identifiant existait,
/// il désignait simplement autre chose.
///
/// ⚠️ `GET /api/pays` EST PUBLIQUE depuis le 25/08/2026, et il le fallait :
/// l'inscription n'a pas encore de jeton d'accès. C'est précisément parce
/// qu'elle ne l'était pas que la liste avait été recopiée en dur.
class PaysRepository {
  PaysRepository(this._api);
  final ApiClient _api;

  /// Cache mémoire : la liste ne change pas d'une ouverture d'écran à l'autre,
  /// et l'inscription n'est pas le moment de faire attendre pour une table de
  /// référence.
  List<Pays>? _cache;

  Future<List<Pays>> liste() async {
    final enCache = _cache;
    if (enCache != null) return enCache;

    final data = await _api.get("/api/pays");
    final brut = data["pays"] as List?;
    final liste = (brut ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Pays.fromJson)
        .toList();
    _cache = liste;
    return liste;
  }
}
