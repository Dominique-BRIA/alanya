import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'media_cache.dart';

/// LA PLACE QU'OCCUPE L'APPLICATION SUR LE TÉLÉPHONE (11/11/2026), reprise de
/// l'écran « Stockage » de l'application de référence.
///
/// Quatre postes, mesurés en parcourant les dossiers :
///  - [medias] : le cache des photos, vidéos et fichiers téléchargés
///    (`MediaCache`) — se vide, tout se retélécharge à l'ouverture ;
///  - [base] : les bases locales (sqflite : discussions, contacts, appels) ;
///  - [temporaires] : le dossier temporaire du système (aperçus déchiffrés,
///    copies de partage, téléchargements en cours…) ;
///  - [autres] : le reste des dossiers de l'application (envois en attente,
///    statuts, sonneries importées…). Il ne se vide pas d'ici : il contient
///    des choses qui n'existent nulle part ailleurs.
class RepartitionStockage {
  const RepartitionStockage({
    this.medias = 0,
    this.base = 0,
    this.temporaires = 0,
    this.autres = 0,
  });

  final int medias;
  final int base;
  final int temporaires;
  final int autres;

  int get total => medias + base + temporaires + autres;
}

class StockageLocal {
  StockageLocal._();

  /// Un fichier temporaire plus récent que cela est laissé en place : il peut
  /// être en train de servir (message vocal en cours d'enregistrement, fichier
  /// qu'on partage à l'instant).
  static const _ageMinimum = Duration(minutes: 10);

  static Future<RepartitionStockage> mesurer() async {
    final cacheMedias = await MediaCache.dossier();
    final medias = await MediaCache.tailleOctets();

    final dossierBases = Directory(await getDatabasesPath());
    final base = await _taille(dossierBases);

    final tmp = await getTemporaryDirectory();
    final temporaires = await _taille(tmp);

    // Le reste : documents et support de l'application, sans ce qui est déjà
    // compté (le cache des médias peut y vivre, et les bases aussi selon la
    // plateforme).
    final exclus = {
      _normaliser(cacheMedias.path),
      _normaliser(dossierBases.path),
      _normaliser(tmp.path),
    };
    var autres = 0;
    for (final d in [
      await getApplicationDocumentsDirectory(),
      await getApplicationSupportDirectory(),
    ]) {
      if (exclus.contains(_normaliser(d.path))) continue;
      autres += await _taille(d, exclus: exclus);
    }

    return RepartitionStockage(
      medias: medias,
      base: base,
      temporaires: temporaires,
      autres: autres,
    );
  }

  static Future<void> viderMedias() => MediaCache.clear();

  /// Vide le dossier temporaire, sauf les fichiers trop récents (voir
  /// [_ageMinimum]). Les dossiers devenus vides sont retirés.
  static Future<void> viderTemporaires() async {
    final tmp = await getTemporaryDirectory();
    if (!await tmp.exists()) return;
    final limite = DateTime.now().subtract(_ageMinimum);
    final dossiers = <Directory>[];
    await for (final e in tmp.list(recursive: true, followLinks: false)) {
      try {
        if (e is File) {
          if ((await e.lastModified()).isBefore(limite)) await e.delete();
        } else if (e is Directory) {
          dossiers.add(e);
        }
      } catch (_) {
        // Fichier occupé ou déjà parti : on passe au suivant.
      }
    }
    // Les plus profonds d'abord.
    dossiers.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final d in dossiers) {
      try {
        if (await d.list().isEmpty) await d.delete();
      } catch (_) {}
    }
  }

  static String _normaliser(String chemin) =>
      chemin.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  static Future<int> _taille(Directory d, {Set<String> exclus = const {}}) async {
    if (!await d.exists()) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final chemin = _normaliser(e.path);
        if (exclus.any((x) => chemin.startsWith('$x/'))) continue;
        try {
          total += await e.length();
        } catch (_) {}
      }
    } catch (_) {
      // Dossier illisible : ce qu'on a déjà compté reste juste.
    }
    return total;
  }

  /// « 12,4 Mo » — [unites] vient des libellés (`stock_unites`, « o|Ko|Mo|Go »).
  static String formater(int octets, String unites, String langue) {
    final u = unites.split('|');
    if (u.length < 4) return '$octets';
    const pas = 1024;
    if (octets < pas) return '$octets ${u[0]}';
    var valeur = octets / pas;
    var rang = 1;
    while (valeur >= pas && rang < 3) {
      valeur /= pas;
      rang++;
    }
    final texte = valeur >= 100 ? valeur.toStringAsFixed(0) : valeur.toStringAsFixed(1);
    // Virgule décimale partout sauf en anglais et en chinois.
    final decimal = (langue == 'en' || langue == 'zh') ? texte : texte.replaceAll('.', ',');
    return '$decimal ${u[rang]}';
  }
}
