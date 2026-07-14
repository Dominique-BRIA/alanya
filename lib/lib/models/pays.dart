/// Modèle Pays tel que renvoyé par l'API — correspond à la table « pays » du PDF.
class Pays {
  final int idPays;
  final String libelle;
  final String prefix; // indicatif téléphonique (+237, +33…)
  final String timeZone;
  final int decalageHoraire; // décalage UTC en minutes

  Pays({
    required this.idPays,
    required this.libelle,
    required this.prefix,
    required this.timeZone,
    required this.decalageHoraire,
  });

  factory Pays.fromJson(Map<String, dynamic> j) => Pays(
        idPays: (j["idPays"] as num).toInt(),
        libelle: j["libelle"] as String,
        prefix: j["prefix"] as String,
        timeZone: j["timeZone"] as String,
        decalageHoraire: (j["decalageHoraire"] as num).toInt(),
      );

  /// Label d'affichage : "Cameroun (+237)"
  String get displayLabel => "$libelle ($prefix)";
}
