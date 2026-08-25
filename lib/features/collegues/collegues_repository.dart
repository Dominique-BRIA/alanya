import '../../core/authed_api.dart';

/// Un service de l'entreprise, avec son effectif.
class ServiceCollegues {
  final String nom;

  /// Nombre de collègues, MOI EXCLU — c'est le serveur qui compte ainsi.
  ///
  /// ⚠️ Zéro est une valeur normale, pas une anomalie : un service peut n'être
  /// tenu que par le standard lui-même, ou par moi seul. L'écran doit le dire
  /// plutôt que de masquer la ligne.
  final int effectif;

  const ServiceCollegues({required this.nom, required this.effectif});

  factory ServiceCollegues.fromJson(Map<String, dynamic> j) => ServiceCollegues(
        nom: j["nom"] as String? ?? "",
        effectif: (j["effectif"] as num?)?.toInt() ?? 0,
      );
}

/// Un collègue : un agent de mon entreprise.
class Collegue {
  final String id;

  /// L'Alanya ID. C'est LUI qui permet d'appeler et d'écrire dans Alanya — le
  /// mobile, lui, sortirait de l'application.
  final String publicNumber;
  final String nom;
  final String? avatarUrl;
  final bool enLigne;

  const Collegue({
    required this.id,
    required this.publicNumber,
    required this.nom,
    required this.avatarUrl,
    required this.enLigne,
  });

  factory Collegue.fromJson(Map<String, dynamic> j) => Collegue(
        id: j["id"] as String? ?? "",
        publicNumber: j["publicNumber"] as String? ?? "",
        nom: j["nom"] as String? ?? "",
        avatarUrl: j["avatarUrl"] as String?,
        enLigne: ((j["isOnline"] as num?)?.toInt() ?? 0) == 1,
      );
}

/// L'annuaire des collègues.
///
/// ⚠️ Le contrat vit côté serveur (`src/lib/collegues.ts`). Ce dépôt ne fait que
/// le traduire en Dart, il n'ajoute aucune règle — en particulier, ce n'est pas
/// lui qui décide qui a le droit de voir l'annuaire.
class ColleguesRepository {
  ColleguesRepository(this._api);
  final AuthedApi _api;

  /// Les services de mon entreprise.
  Future<List<ServiceCollegues>> services() async {
    final data = await _api.get("/api/collegues");
    final brut = data["services"] as List?;
    return (brut ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceCollegues.fromJson)
        .toList();
  }

  /// Les collègues d'un service.
  Future<List<Collegue>> membres(String service) async {
    final data =
        await _api.get("/api/collegues?service=${Uri.encodeQueryComponent(service)}");
    return _collegues(data);
  }

  /// Recherche parmi TOUS les collègues de l'entreprise.
  ///
  /// 🔴 NE PASSE PAS PAR LES SERVICES, et c'est tout son intérêt : un agent
  /// peut n'être rattaché à aucun service — cas réel en production — et la
  /// navigation par service ne peut alors pas l'atteindre.
  Future<List<Collegue>> chercher(String requete) async {
    final data =
        await _api.get("/api/collegues?q=${Uri.encodeQueryComponent(requete)}");
    return _collegues(data);
  }

  List<Collegue> _collegues(Map<String, dynamic> data) {
    final brut = data["collegues"] as List?;
    return (brut ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Collegue.fromJson)
        .toList();
  }
}
