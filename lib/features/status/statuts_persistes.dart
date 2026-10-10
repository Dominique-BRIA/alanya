import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// LES STATUTS QUI ATTENDENT LE RÉSEAU, GARDÉS SUR DISQUE.
///
/// 🔴 SANS CELA, LA PHOTO EST PERDUE. Publier un statut se fait en deux temps —
/// téléverser le fichier, puis déclarer le statut qui le cite. Sans réseau, le
/// premier est impossible : `PublicationStatuts` marquait le transfert en échec,
/// une ligne rouge restait dans la barre système, et la photo n'existait plus
/// nulle part. Il fallait la reprendre, la recadrer, la réannoter.
///
/// ⚠️ LE RÉPERTOIRE **DOCUMENTS**, PAS LE CACHE — même raison que pour les
/// envois de discussion : le système vide le cache quand l'espace manque,
/// c'est-à-dire au moment précis où il tue l'application.
///
/// 🔴 UN STATUT EN ATTENTE PÉRIME AU BOUT DE 24 H, contrairement à un média de
/// discussion qui, lui, attend indéfiniment. La raison n'est pas technique : un
/// statut NE PORTE PAS SA DATE. Le serveur le date au moment où il le REÇOIT et
/// le montre vingt-quatre heures à partir de là. Republier trois jours plus tard
/// une photo prise lundi la présenterait donc comme prise à l'instant, à tout le
/// répertoire, sans que personne l'ait demandé. Un message, lui, garde son
/// horodatage et reste juste.
///
/// Vingt-quatre heures, parce qu'au-delà le statut aurait de toute façon expiré
/// s'il était parti tout de suite : on ne publie pas ce que son auteur ne
/// verrait même plus.
///
/// ⚠️ Ces fichiers sont ceux d'APRÈS transcodage. Une vidéo de statut est
/// recompressée avant l'envoi, et c'est long : ranger l'original obligerait à
/// tout refaire à chaque reprise, batterie comprise.
class StatutsPersistes {
  StatutsPersistes._();

  /// Au-delà, l'entrée est abandonnée — voir la note de classe.
  static const peremption = Duration(hours: 24);

  static Database? _db;
  static Directory? _dossier;

  static Future<Database> _base() async {
    if (_db != null) return _db!;
    final chemin = await getDatabasesPath();
    _db = await openDatabase(
      p.join(chemin, 'alanya_statuts_attente.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE statuts (
            id TEXT PRIMARY KEY,
            meta TEXT NOT NULL,
            cree_a INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<Directory> _racine() async {
    if (_dossier != null) return _dossier!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'statuts_en_attente'));
    if (!await d.exists()) await d.create(recursive: true);
    _dossier = d;
    return d;
  }

  /// Range un statut en attente. [mediaId] est fourni quand le téléversement
  /// avait déjà abouti et que seule la déclaration a échoué.
  static Future<void> enregistrer({
    required String id,
    required Uint8List octets,
    required String nomFichier,
    required String mimeType,
    int? durationMs,
    String? legende,
    String? mediaId,
    DateTime? creeA,
  }) async {
    try {
      final racine = await _racine();
      final sur = nomFichier.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final chemin = p.join(racine.path, '${id}_$sur');
      final cible = File(chemin);
      // Les octets ne sont écrits qu'une fois : cette méthode est rappelée à
      // chaque tentative ratée.
      if (!await cible.exists()) await cible.writeAsBytes(octets, flush: true);

      final db = await _base();
      final date = creeA ?? DateTime.now();
      await db.insert(
        'statuts',
        {
          'id': id,
          'cree_a': date.millisecondsSinceEpoch,
          'meta': jsonEncode({
            'chemin': chemin,
            'nom': nomFichier,
            'mime': mimeType,
            'dureeMs': durationMs,
            'legende': legende,
            'mediaId': mediaId,
            'creeA': date.toIso8601String(),
          }),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[statuts] enregistrement impossible : $e');
    }
  }

  static Future<void> oublier(String id) async {
    Map<String, dynamic>? meta;
    try {
      final db = await _base();
      final lignes =
          await db.query('statuts', where: 'id = ?', whereArgs: [id], limit: 1);
      if (lignes.isNotEmpty) {
        meta = jsonDecode(lignes.first['meta'] as String) as Map<String, dynamic>;
      }
      await db.delete('statuts', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
    try {
      final chemin = meta?['chemin'] as String?;
      if (chemin != null) {
        final f = File(chemin);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  /// Combien attendent encore, périmés exclus.
  static Future<int> compter() async {
    try {
      final db = await _base();
      final seuil = DateTime.now().subtract(peremption).millisecondsSinceEpoch;
      final lignes =
          await db.query('statuts', where: 'cree_a > ?', whereArgs: [seuil]);
      return lignes.length;
    } catch (_) {
      return 0;
    }
  }

  /// Relit tout ce qui attend, du plus ancien au plus récent.
  ///
  /// Les entrées périmées et celles dont le fichier a disparu sont effacées au
  /// passage : les laisser ferait grossir le dossier sans que rien ne les
  /// utilise jamais.
  static Future<List<StatutEnAttente>> charger() async {
    final sortie = <StatutEnAttente>[];
    try {
      final db = await _base();
      final lignes = await db.query('statuts', orderBy: 'cree_a ASC');
      final limite = DateTime.now().subtract(peremption);

      for (final ligne in lignes) {
        final id = ligne['id'] as String;
        try {
          final meta = jsonDecode(ligne['meta'] as String) as Map<String, dynamic>;
          final creeA =
              DateTime.tryParse(meta['creeA'] as String? ?? '') ?? DateTime.now();
          if (creeA.isBefore(limite)) {
            await oublier(id);
            continue;
          }
          final f = File(meta['chemin'] as String);
          if (!await f.exists()) {
            await oublier(id);
            continue;
          }
          sortie.add(StatutEnAttente(
            id: id,
            octets: Uint8List.fromList(await f.readAsBytes()),
            nomFichier: meta['nom'] as String,
            mimeType: meta['mime'] as String,
            durationMs: meta['dureeMs'] as int?,
            legende: meta['legende'] as String?,
            mediaId: meta['mediaId'] as String?,
            creeA: creeA,
          ));
        } catch (e) {
          debugPrint('[statuts] entrée illisible, ignorée : $e');
          await oublier(id);
        }
      }
    } catch (e) {
      debugPrint('[statuts] relecture impossible : $e');
    }
    return sortie;
  }
}

/// Un statut relu du disque, prêt à repartir.
class StatutEnAttente {
  const StatutEnAttente({
    required this.id,
    required this.octets,
    required this.nomFichier,
    required this.mimeType,
    required this.durationMs,
    required this.legende,
    required this.mediaId,
    required this.creeA,
  });

  final String id;
  final Uint8List octets;
  final String nomFichier;
  final String mimeType;
  final int? durationMs;
  final String? legende;

  /// Déjà téléversé : seule la déclaration reste à faire.
  ///
  /// ⚠️ Le garder évite de renvoyer les octets une seconde fois — et d'ajouter
  /// un média orphelin en base, que plus aucun statut ne citerait.
  final String? mediaId;

  final DateTime creeA;
}
