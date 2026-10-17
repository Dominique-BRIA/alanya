import '../../core/authed_api.dart';

/// L'EXPORT DES MÉDIAS REÇUS — le décompte, et l'adresse de l'archive.
///
/// 🔴 L'ARCHIVE N'EST PAS CONSTRUITE ICI. Le serveur la fabrique au fil de
/// l'eau et l'envoie ; le téléphone ne fait que la recevoir et l'écrire. La
/// construire côté application obligerait à télécharger chaque fichier un par
/// un, à tout garder en mémoire, puis à réécrire — deux fois le transfert, sur
/// un forfait mobile, avec une application que le système peut tuer au milieu.
class ExportMediasRepository {
  ExportMediasRepository(this._api);

  final AuthedApi _api;

  /// Les familles proposées — mêmes noms que côté serveur, aucune traduction.
  static const familles = ['photo', 'video', 'audio', 'document'];

  /// Combien de fichiers, quel poids, et à partir de quand c'est trop.
  Future<ChiffrageExport> chiffrer(CriteresExport criteres) async {
    final res = await _api.get('/api/exports/medias?compter=1&${criteres.enParametres()}');
    return ChiffrageExport(
      fichiers: (res['fichiers'] as num?)?.toInt() ?? 0,
      octets: (res['octets'] as num?)?.toInt() ?? 0,
      plafondOctets: (res['plafondOctets'] as num?)?.toInt() ?? 0,
    );
  }

  /// Le chemin de l'archive, à faire suivre au téléchargeur.
  String chemin(CriteresExport criteres) => '/api/exports/medias?${criteres.enParametres()}';
}

class ChiffrageExport {
  const ChiffrageExport({
    required this.fichiers,
    required this.octets,
    required this.plafondOctets,
  });

  final int fichiers;
  final int octets;
  final int plafondOctets;

  bool get tropGros => plafondOctets > 0 && octets > plafondOctets;
}

class CriteresExport {
  const CriteresExport({
    this.conversations = const [],
    this.familles = const [],
    this.du,
    this.au,
  });

  /// Vide = toutes mes discussions.
  final List<String> conversations;
  final List<String> familles;
  final DateTime? du;
  final DateTime? au;

  bool get valide => familles.isNotEmpty && !periodeInversee;

  bool get periodeInversee =>
      du != null && au != null && du!.isAfter(au!);

  /// Les critères, mis en paramètres d'URL.
  ///
  /// ⚠️ LES DATES PARTENT EN UTC. Un `DateTime` choisi dans un sélecteur est
  /// LOCAL ; l'envoyer tel quel ferait lire au serveur une heure qui n'est pas
  /// celle de l'utilisateur, et quelqu'un à Douala exporterait une tranche
  /// décalée d'une heure sans jamais comprendre pourquoi.
  String enParametres() {
    final p = <String>['familles=${familles.join(',')}'];
    if (conversations.isNotEmpty) {
      p.add('conversations=${conversations.map(Uri.encodeComponent).join(',')}');
    }
    if (du != null) p.add('du=${Uri.encodeComponent(du!.toUtc().toIso8601String())}');
    if (au != null) p.add('au=${Uri.encodeComponent(au!.toUtc().toIso8601String())}');
    return p.join('&');
  }
}

/// « 1,4 Go », « 812 Mo » — la taille telle qu'on la lit.
String tailleLisible(int octets) {
  if (octets <= 0) return '0 o';
  const unites = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var valeur = octets.toDouble();
  var rang = 0;
  while (valeur >= 1024 && rang < unites.length - 1) {
    valeur /= 1024;
    rang++;
  }
  // Une décimale au-delà du kilo-octet, aucune en dessous : « 1,4 Go » se lit,
  // « 1,437 Go » se déchiffre.
  final texte = rang > 1 ? valeur.toStringAsFixed(1) : valeur.round().toString();
  return '$texte ${unites[rang]}';
}
