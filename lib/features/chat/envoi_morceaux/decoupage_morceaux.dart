/// LE DÉCOUPAGE D'UN ENVOI EN MORCEAUX, et le pourcentage qu'on en montre.
///
/// Jumeau de `backend-alanya/src/lib/envoi-morceaux.mjs` : c'est LE SERVEUR
/// qui décide de la taille d'un morceau (rendue à la réservation) ; ce fichier
/// refait seulement les mêmes calculs pour savoir quelles tranches envoyer.
/// Toute évolution du découpage se fait côté serveur d'abord.
library;

/// Une tranche du fichier chiffré, envoyée en une requête.
class Morceau {
  const Morceau(this.indice, this.debut, this.fin);

  /// Numéro du morceau, à partir de 0 — celui de l'adresse `…/morceaux/:n`.
  final int indice;

  /// Premier octet (inclus).
  final int debut;

  /// Fin (EXCLUE).
  final int fin;

  int get taille => fin - debut;

  /// L'en-tête `Range` que lit `background_downloader` pour n'envoyer que
  /// cette tranche du fichier. ⚠️ La borne de fin y est INCLUSE.
  String get plage => 'bytes=$debut-${fin - 1}';
}

/// Les morceaux d'un fichier de [taille] octets, en tranches de [tailleMorceau].
///
/// Un fichier vide fait UN morceau vide — mais un chiffré AGB1 n'est jamais
/// vide (16 octets d'étiquette au moins), et le serveur refuse une taille nulle.
List<Morceau> morceauxDe(int taille, int tailleMorceau) {
  if (taille <= 0 || tailleMorceau <= 0) {
    throw ArgumentError('taille et taille de morceau doivent être positives');
  }
  final nb = (taille + tailleMorceau - 1) ~/ tailleMorceau;
  return List.generate(nb, (i) {
    final debut = i * tailleMorceau;
    final fin = debut + tailleMorceau > taille ? taille : debut + tailleMorceau;
    return Morceau(i, debut, fin);
  });
}

/// L'avancement d'un envoi, en OCTETS et non en morceaux.
///
/// ⚠️ PONDÉRÉ PAR LA TAILLE : le dernier morceau est souvent plus court ; le
/// compter comme les autres ferait sauter le pourcentage à la fin.
///
/// ⚠️ JAMAIS 100 % AVANT LA RÉPONSE DU SERVEUR. Les octets peuvent être tous
/// partis alors que l'assemblage et la publication restent à faire : afficher
/// « 100 % » ferait croire le message arrivé. On plafonne à 99 % jusqu'à
/// [terminer].
class ProgressionEnvoi {
  ProgressionEnvoi(List<Morceau> morceaux)
      : _tailles = {for (final m in morceaux) m.indice: m.taille},
        _total = morceaux.fold<int>(0, (s, m) => s + m.taille);

  final Map<int, int> _tailles;
  final int _total;
  final Map<int, double> _avance = {};
  bool _termine = false;

  /// Le morceau [indice] en est à [fraction] (0 à 1).
  void avancer(int indice, double fraction) {
    if (!_tailles.containsKey(indice) || fraction.isNaN) return;
    final f = fraction.clamp(0.0, 1.0);
    // Une progression ne recule pas : un réessai repart de 0, mais l'écran
    // ne doit pas voir la barre redescendre (déjà-vu sur `onProgress`).
    if (f > (_avance[indice] ?? 0)) _avance[indice] = f;
  }

  /// Le morceau [indice] est arrivé (le serveur l'a accepté).
  void morceauRecu(int indice) => avancer(indice, 1);

  /// Les morceaux que le serveur dit avoir déjà (reprise après redémarrage).
  void dejaRecus(Iterable<int> indices) {
    for (final i in indices) {
      morceauRecu(i);
    }
  }

  /// Le serveur a assemblé le fichier : c'est maintenant, et seulement
  /// maintenant, 100 %.
  void terminer() => _termine = true;

  double get fraction {
    if (_termine) return 1;
    if (_total == 0) return 0;
    var faits = 0.0;
    _avance.forEach((i, f) => faits += f * _tailles[i]!);
    final brut = faits / _total;
    return brut >= 0.99 ? 0.99 : brut;
  }

  /// Ce qu'affichent la bulle et la notification : 0 à 100.
  int get pourcent => (fraction * 100).floor();
}
