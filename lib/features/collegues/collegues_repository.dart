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

  /// L agence de rattachement, ou null.
  ///
  /// NUL, ET JAMAIS UNE CHAINE VIDE : un agent sans fonction rattachee n a pas
  /// d agence, et le cas est REEL en production. Le distinguer permet de ne
  /// RIEN afficher, la ou un libelle vide dessinerait une ligne creuse sous le
  /// numero — qui se lit comme une donnee perdue plutot que comme une
  /// information qui n existe pas.
  final String? agence;

  const Collegue({
    required this.id,
    required this.publicNumber,
    required this.nom,
    required this.avatarUrl,
    required this.enLigne,
    this.agence,
  });

  factory Collegue.fromJson(Map<String, dynamic> j) => Collegue(
        id: j["id"] as String? ?? "",
        publicNumber: j["publicNumber"] as String? ?? "",
        nom: j["nom"] as String? ?? "",
        avatarUrl: j["avatarUrl"] as String?,
        enLigne: ((j["isOnline"] as num?)?.toInt() ?? 0) == 1,
        // Un libelle vide vaut absence : le serveur rend null, mais une base
        // qui porterait une chaine vide ne doit pas produire une ligne creuse.
        agence: (j["agence"] as String?)?.trim().isNotEmpty == true
            ? (j["agence"] as String).trim()
            : null,
      );
}

/// Les services, ET la raison d'une liste vide.
///
/// 🔴 LES DEUX ENSEMBLE, parce qu'une liste vide seule ne dit pas POURQUOI.
/// L'écran affichait « Aucun service n'est configuré pour ton entreprise » dans
/// tous les cas ; depuis que l'entreprise peut resserrer le répertoire au propre
/// service de l'agent, ce texte peut être faux — des services existent, on n'a
/// simplement pas le droit de les voir. Envoyer quelqu'un signaler une panne de
/// configuration qui n'existe pas coûte plus cher qu'un booléen.
class ListeServices {
  const ListeServices({required this.services, required this.porteeRestreinte});

  final List<ServiceCollegues> services;

  /// L'entreprise limite le répertoire au service de chacun (`company.collegue`
  /// à 0). Faux par défaut : c'est le comportement d'avant ce réglage, et un
  /// serveur qui ne renvoie pas le champ ne doit pas faire croire à une
  /// restriction.
  final bool porteeRestreinte;
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
  Future<ListeServices> services() async {
    final data = await _api.get("/api/collegues");
    final brut = data["services"] as List?;
    return ListeServices(
      services: (brut ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServiceCollegues.fromJson)
          .toList(),
      porteeRestreinte: data["porteeRestreinte"] as bool? ?? false,
    );
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
