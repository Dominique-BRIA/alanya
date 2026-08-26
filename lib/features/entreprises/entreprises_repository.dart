import '../../core/authed_api.dart';

/// Un type d'entreprise, avec le nombre d'entreprises visibles derrière.
class TypeEntreprise {
  final int id;
  final String libelle;

  /// ⚠️ COMPTE D'APRÈS FILTRE, pays compris — c'est le serveur qui le calcule.
  /// Zéro veut dire « aucune dans ton pays », pas « aucune du tout » : la
  /// recherche, elle, peut encore en trouver.
  final int nbEntreprises;

  const TypeEntreprise({
    required this.id,
    required this.libelle,
    required this.nbEntreprises,
  });

  factory TypeEntreprise.fromJson(Map<String, dynamic> j) => TypeEntreprise(
        id: (j["idTypeCompany"] as num?)?.toInt() ?? 0,
        libelle: j["libelle"] as String? ?? "",
        nbEntreprises: (j["nbEntreprises"] as num?)?.toInt() ?? 0,
      );
}

/// Une entreprise de l'annuaire.
class Entreprise {
  final int id;
  final String libelle;
  final String? description;
  final String? adresse;

  /// Le pays, `null` quand il n'est pas renseigné en base.
  ///
  /// ⚠️ Une entreprise sans pays n'apparaît QUE dans la recherche : elle ne
  /// peut être rattachée à aucune liste filtrée. Le cas est réel en production.
  final String? pays;
  final String? ville;

  const Entreprise({
    required this.id,
    required this.libelle,
    required this.description,
    required this.adresse,
    required this.pays,
    required this.ville,
  });

  factory Entreprise.fromJson(Map<String, dynamic> j) => Entreprise(
        id: (j["idCompany"] as num?)?.toInt() ?? 0,
        libelle: j["libelle"] as String? ?? "",
        description: _texte(j["description"]),
        adresse: _texte(j["adresse"]),
        pays: _texte((j["pays"] as Map<String, dynamic>?)?["libelle"]),
        ville: _texte((j["ville"] as Map<String, dynamic>?)?["nom"]),
      );

  /// Les colonnes valent `""` aussi souvent que `null` en base — les deux
  /// disent la même chose, et l'écran ne doit afficher ni l'une ni l'autre.
  static String? _texte(Object? v) {
    final s = (v as String?)?.trim() ?? "";
    return s.isEmpty ? null : s;
  }
}

/// Un service, derrière une touche du menu.
class ServiceTouche {
  /// Le chiffre à composer une fois le standard décroché.
  final int touche;

  /// Le nom du service, ou `null` s'il n'est pas renseigné.
  ///
  /// 🔴 L'ÉCRAN AFFICHE ALORS « Sans nom », traduit — jamais un libellé
  /// fabriqué. Le serveur ne renvoie volontairement rien : « Touche 2 »
  /// ressemblerait à un vrai intitulé, et serait du français servi aux neuf
  /// langues.
  final String? nom;

  const ServiceTouche({required this.touche, required this.nom});

  factory ServiceTouche.fromJson(Map<String, dynamic> j) => ServiceTouche(
        touche: (j["touche"] as num?)?.toInt() ?? 0,
        nom: (j["nom"] as String?)?.trim().isEmpty ?? true
            ? null
            : (j["nom"] as String).trim(),
      );
}

/// Un standard : centre d'appel (humain) ou centre vocal.
class CentreEntreprise {
  /// `appel` ou `vocal`.
  final String type;
  final String nom;

  /// 🔴 L'ALANYA ID À COMPOSER. C'est lui qu'on appelle pour tomber sur le
  /// standard, jamais le numéro court de l'entreprise — qui ne distingue pas
  /// les centres entre eux.
  final String alanyaId;

  final List<ServiceTouche> services;

  const CentreEntreprise({
    required this.type,
    required this.nom,
    required this.alanyaId,
    required this.services,
  });

  bool get estVocal => type == "vocal";

  factory CentreEntreprise.fromJson(Map<String, dynamic> j) => CentreEntreprise(
        type: j["type"] as String? ?? "appel",
        nom: j["nom"] as String? ?? "",
        alanyaId: j["alanyaId"] as String? ?? "",
        services: ((j["services"] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ServiceTouche.fromJson)
            .toList(),
      );
}

/// La fiche d'une entreprise : l'entreprise et ses standards.
class FicheEntreprise {
  final Entreprise entreprise;
  final List<CentreEntreprise> centres;
  const FicheEntreprise({required this.entreprise, required this.centres});
}

/// L'annuaire des entreprises.
///
/// ⚠️ Le contrat vit côté serveur (`src/lib/annuaire-entreprises.ts`). Ce dépôt
/// ne fait que le traduire ; en particulier ce n'est pas lui qui décide quelles
/// entreprises sont visibles — le filtre par pays est appliqué au serveur, qui
/// lit le pays du compte plutôt que de le croire sur parole.
class EntreprisesRepository {
  EntreprisesRepository(this._api);
  final AuthedApi _api;

  /// Les types d'entreprise.
  Future<List<TypeEntreprise>> types() async {
    final data = await _api.get("/api/entreprises");
    return ((data["types"] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TypeEntreprise.fromJson)
        .toList();
  }

  /// Les entreprises d'un type, DANS MON PAYS.
  Future<List<Entreprise>> duType(int idType) async {
    final data = await _api.get("/api/entreprises?type=$idType");
    return _entreprises(data);
  }

  /// Recherche — TOUS PAYS confondus.
  ///
  /// 🔴 Seul chemin vers une entreprise dont le pays n'est pas renseigné : la
  /// navigation par type ne peut pas l'atteindre.
  Future<List<Entreprise>> chercher(String requete) async {
    final data =
        await _api.get("/api/entreprises?q=${Uri.encodeQueryComponent(requete)}");
    return _entreprises(data);
  }

  /// La fiche d'une entreprise : ses centres et leurs services.
  Future<FicheEntreprise> fiche(int idEntreprise) async {
    final data = await _api.get("/api/entreprises?entreprise=$idEntreprise");
    return FicheEntreprise(
      entreprise:
          Entreprise.fromJson(data["entreprise"] as Map<String, dynamic>? ?? const {}),
      centres: ((data["centres"] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CentreEntreprise.fromJson)
          .toList(),
    );
  }

  List<Entreprise> _entreprises(Map<String, dynamic> data) =>
      ((data["entreprises"] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Entreprise.fromJson)
          .toList();
}
