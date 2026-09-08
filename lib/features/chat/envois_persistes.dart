import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../widgets/media/media_picker_sheet.dart';
import 'envoi_media.dart';

/// LES ENVOIS DE MÉDIAS QUI ATTENDENT LE RÉSEAU, GARDÉS SUR DISQUE.
///
/// 🔴 SANS CELA, ANDROID PERD LE FICHIER. Les envois en attente vivaient
/// uniquement dans la mémoire de `EnvoiMediaStore`. Or le système tue une
/// application passée en arrière-plan dès qu'il a besoin de place — c'est le cas
/// NORMAL, pas l'accident : on envoie une photo dans le métro, on range son
/// téléphone, l'application est tuée, et la photo n'existe plus nulle part. La
/// bulle avait pourtant promis qu'elle partirait toute seule.
///
/// ⚠️ LE RÉPERTOIRE **DOCUMENTS**, ET SURTOUT PAS LE CACHE. Android et iOS
/// vident le cache quand l'espace manque — exactement les circonstances où
/// l'application est tuée. Y ranger ces fichiers reviendrait à les perdre au
/// pire moment, avec l'illusion de les avoir sauvés.
///
/// ⚠️ AUCUNE PÉREMPTION. Un envoi en attente reste tant qu'il n'est pas parti ou
/// que l'utilisateur ne l'a pas supprimé, et sa bulle porte le bouton pour cela.
/// L'effacer au bout de quelques jours serait une perte SILENCIEUSE d'un fichier
/// que l'écran continue de montrer — précisément ce que tout ce travail
/// corrige. Un statut, lui, périme : il porte une date que le serveur relit.
class EnvoisPersistes {
  EnvoisPersistes._();

  static Database? _db;
  static Directory? _dossier;

  static Future<Database> _base() async {
    if (_db != null) return _db!;
    final chemin = await getDatabasesPath();
    _db = await openDatabase(
      p.join(chemin, 'alanya_envois_media.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE envois (
            temp_id TEXT PRIMARY KEY,
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
    final d = Directory(p.join(docs.path, 'envois_en_attente'));
    if (!await d.exists()) await d.create(recursive: true);
    _dossier = d;
    return d;
  }

  /// Range un envoi sur disque. Sans effet s'il y est déjà à l'identique.
  ///
  /// ⚠️ LES OCTETS NE SONT ÉCRITS QU'UNE FOIS. Cette méthode est rappelée à
  /// chaque tentative ratée : réécrire dix mégaoctets à chaque échec userait la
  /// mémoire flash pour rien, et ralentirait chaque reprise.
  static Future<void> enregistrer(EnvoiMedia envoi) async {
    try {
      final racine = await _racine();
      final dossier = Directory(p.join(racine.path, envoi.tempId));
      if (!await dossier.exists()) await dossier.create(recursive: true);

      final fichiers = <Map<String, dynamic>>[];
      for (var i = 0; i < envoi.fichiers.length; i++) {
        final f = envoi.fichiers[i];
        // Le nom d'origine peut porter n'importe quoi — des barres obliques
        // comprises, qui creuseraient une arborescence. On le neutralise, et on
        // garde le vrai nom dans les métadonnées.
        final sur = f.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final chemin = p.join(dossier.path, '${i}_$sur');
        final cible = File(chemin);
        if (!await cible.exists()) await cible.writeAsBytes(f.bytes, flush: true);
        fichiers.add({
          'nom': f.fileName,
          'mime': f.mimeType,
          'dureeMs': f.durationMs,
          'chemin': chemin,
        });
      }

      final db = await _base();
      await db.insert(
        'envois',
        {
          'temp_id': envoi.tempId,
          'cree_a': envoi.creeA.millisecondsSinceEpoch,
          'meta': jsonEncode({
            'convId': envoi.convId,
            'msgType': envoi.msgType,
            'legende': envoi.legende,
            'replyToId': envoi.replyToId,
            'mentions': envoi.mentions,
            'creeA': envoi.creeA.toIso8601String(),
            'mediaIdsObtenus': envoi.mediaIdsObtenus,
            'fichiers': fichiers,
          }),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Disque plein, permission refusée : l'envoi continue de vivre en
      // mémoire. On perd la survie au redémarrage, pas l'envoi lui-même.
      debugPrint('[envois] enregistrement impossible : $e');
    }
  }

  /// Oublie un envoi : sa ligne et ses fichiers.
  static Future<void> oublier(String tempId) async {
    try {
      final db = await _base();
      await db.delete('envois', where: 'temp_id = ?', whereArgs: [tempId]);
    } catch (_) {}
    try {
      final racine = await _racine();
      final dossier = Directory(p.join(racine.path, tempId));
      if (await dossier.exists()) await dossier.delete(recursive: true);
    } catch (_) {}
  }

  /// Relit tout ce qui attendait, du plus ancien au plus récent.
  ///
  /// ⚠️ UNE ENTRÉE DONT UN FICHIER MANQUE EST JETÉE, elle et ses fichiers. Un
  /// envoi amputé partirait incomplet — trois photos sur cinq — sans que rien ne
  /// le dise. Mieux vaut qu'il ait disparu franchement que d'arriver faux.
  static Future<List<EnvoiMedia>> charger() async {
    final restaures = <EnvoiMedia>[];
    try {
      final db = await _base();
      final lignes = await db.query('envois', orderBy: 'cree_a ASC');

      for (final ligne in lignes) {
        final tempId = ligne['temp_id'] as String;
        try {
          final meta = jsonDecode(ligne['meta'] as String) as Map<String, dynamic>;
          final bruts = (meta['fichiers'] as List).cast<Map<String, dynamic>>();

          final fichiers = <MediaPickResult>[];
          var complet = true;
          for (final b in bruts) {
            final f = File(b['chemin'] as String);
            if (!await f.exists()) {
              complet = false;
              break;
            }
            fichiers.add(MediaPickResult(
              bytes: Uint8List.fromList(await f.readAsBytes()),
              fileName: b['nom'] as String,
              mimeType: b['mime'] as String,
              durationMs: b['dureeMs'] as int?,
              // Le chemin sert à l'aperçu d'une vidéo, qui lit un fichier et
              // jamais des octets. Celui d'origine a pu disparaître ; celui-ci
              // est à nous et vivra aussi longtemps que l'envoi.
              path: b['chemin'] as String,
            ));
          }
          if (!complet || fichiers.isEmpty) {
            await oublier(tempId);
            continue;
          }

          final envoi = EnvoiMedia(
            tempId: tempId,
            convId: meta['convId'] as String,
            fichiers: fichiers,
            msgType: meta['msgType'] as String,
            legende: meta['legende'] as String?,
            replyToId: meta['replyToId'] as String?,
            mentions: (meta['mentions'] as List?)
                ?.map((m) => Map<String, String>.from(m as Map))
                .toList(),
            creeA: DateTime.tryParse(meta['creeA'] as String? ?? ''),
          );
          // ⚠️ CE QUI ÉTAIT DÉJÀ TÉLÉVERSÉ NE REPART PAS. Sur cinq photos dont
          // trois étaient passées avant la coupure, les recommencer coûterait
          // trois téléversements pour rien et laisserait trois médias orphelins
          // en base, référencés par aucun message.
          envoi.mediaIdsObtenus
              .addAll((meta['mediaIdsObtenus'] as List).cast<String>());
          envoi.enAttenteReseau = true;
          restaures.add(envoi);
        } catch (e) {
          debugPrint('[envois] entrée illisible, ignorée : $e');
          await oublier(tempId);
        }
      }
    } catch (e) {
      debugPrint('[envois] relecture impossible : $e');
    }
    return restaures;
  }
}
