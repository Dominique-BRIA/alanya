import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/message.dart';

/// Cache local des messages (offline-first).
///
/// Stocke les messages dans une base SQLite locale. Au chargement d'une
/// conversation, on affiche d'abord le cache (instantané), puis on synchronise
/// avec le serveur en arrière-plan pour récupérer les nouveaux messages.
class MessageCache {
  MessageCache._();
  static Database? _db;

  /// Ouvre (ou crée) la base de données locale.
  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'alanya_messages.db'),
      /*
       * 🔴 VERSION 2 — ET LA PREMIÈRE MIGRATION DE CE CACHE.
       *
       * La base était en `version: 1` sans `onUpgrade` : toute colonne ajoutée
       * n'aurait jamais existé chez ceux qui ont déjà l'application, sans la
       * moindre erreur — `onCreate` ne s'exécute que sur une base neuve. C'est
       * exactement le mécanisme qui a coûté plusieurs pannes côté serveur avec
       * `prisma/migrations`.
       *
       * Toute évolution future de ce cache passe désormais par `onUpgrade`, en
       * incrémentant `version`.
       */
      version: 2,
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) await _creeTableTraductions(db);
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conv_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            content TEXT,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            reply_to_id TEXT,
            reply_to_snapshot TEXT,
            deleted_at TEXT,
            created_at TEXT NOT NULL,
            media_json TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_conv ON messages(conv_id, created_at)',
        );
        await _creeTableTraductions(db);
      },
    );
    return _db!;
  }

  /*
   * ═══ TRADUCTIONS ═══
   *
   * 🔴 TABLE À PART, ET C'EST LA DÉCISION CENTRALE DE CE LOT.
   *
   * `putConv` EFFACE tous les messages d'une conversation avant de réinsérer ce
   * que le serveur vient de rendre. Des colonnes de traduction posées sur
   * `messages` seraient donc balayées à CHAQUE rafraîchissement du fil — la
   * traduction aurait survécu à la sortie de l'écran, mais pas à la première
   * synchronisation, ce qui est pire : le défaut serait devenu intermittent.
   *
   * Une table indépendante ne connaît pas ce cycle. Elle porte `conv_id` pour
   * charger un fil en une requête, et pour se purger avec lui.
   */
  static Future<void> _creeTableTraductions(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS traductions (
        message_id TEXT PRIMARY KEY,
        conv_id TEXT NOT NULL,
        texte TEXT NOT NULL,
        langue_source TEXT,
        langue_cible TEXT NOT NULL,
        cree_le TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_traductions_conv ON traductions(conv_id, langue_cible)',
    );
  }

  /// Retient la traduction d'un message.
  ///
  /// ⚠️ [langueCible] EST STOCKÉE AVEC LE TEXTE. Une traduction ne vaut que
  /// pour la langue vers laquelle elle a été faite : sans cette colonne, un
  /// utilisateur qui change de langue de lecture verrait ressortir ses
  /// anciennes traductions, dans la mauvaise langue, sans aucun moyen de s'en
  /// apercevoir.
  static Future<void> putTraduction({
    required String messageId,
    required String convId,
    required String texte,
    required String? langueSource,
    required String langueCible,
  }) async {
    final db = await _database();
    await db.insert(
      'traductions',
      {
        'message_id': messageId,
        'conv_id': convId,
        'texte': texte,
        'langue_source': langueSource,
        'langue_cible': langueCible,
        'cree_le': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Les traductions d'une conversation vers [langueCible].
  ///
  /// Filtré sur la langue : ce qui a été traduit vers une autre langue n'est
  /// pas rendu, mais reste en base — l'utilisateur peut revenir à sa langue
  /// précédente, et retrouver son fil déjà traduit.
  static Future<Map<String, String>> traductionsDe(
    String convId,
    String langueCible,
  ) async {
    final db = await _database();
    final rows = await db.query(
      'traductions',
      columns: ['message_id', 'texte'],
      where: 'conv_id = ? AND langue_cible = ?',
      whereArgs: [convId, langueCible],
    );
    return {
      for (final r in rows) r['message_id'] as String: r['texte'] as String,
    };
  }

  /// Oublie la traduction d'un message — quand l'utilisateur la retire.
  ///
  /// Sans cela, retirer une traduction ne durerait que le temps de l'écran :
  /// elle reviendrait à la réouverture, et le geste passerait pour ignoré.
  static Future<void> supprimeTraduction(String messageId) async {
    final db = await _database();
    await db.delete('traductions', where: 'message_id = ?', whereArgs: [messageId]);
  }

  /// Sauvegarde (ou met à jour) une liste de messages pour une conversation.
  /// Remplace entièrement les messages existants de cette conversation.
  static Future<void> putConv(String convId, List<Message> messages) async {
    final db = await _database();
    final batch = db.batch();

    // Supprime les anciens messages de cette conversation.
    batch.delete(
      'messages',
      where: 'conv_id = ?',
      whereArgs: [convId],
    );

    // Insère les nouveaux.
    for (final m in messages) {
      batch.insert(
        'messages',
        {
          'id': m.id,
          'conv_id': convId,
          'sender_id': m.senderId,
          'content': m.content,
          'type': m.type,
          'status': m.status,
          'reply_to_id': m.replyToId,
          'reply_to_snapshot':
              m.replyTo != null ? jsonEncode(_replyToJson(m.replyTo!)) : null,
          'deleted_at': m.deletedAt?.toIso8601String(),
          'created_at': m.createdAt.toIso8601String(),
          'media_json': m.media.isNotEmpty ? jsonEncode(_mediaListToJson(m.media)) : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Ajoute ou met à jour un seul message (sans tout effacer).
  static Future<void> upsert(Message m, String convId) async {
    final db = await _database();
    await db.insert(
      'messages',
      {
        'id': m.id,
        'conv_id': convId,
        'sender_id': m.senderId,
        'content': m.content,
        'type': m.type,
        'status': m.status,
        'reply_to_id': m.replyToId,
        'reply_to_snapshot':
            m.replyTo != null ? jsonEncode(_replyToJson(m.replyTo!)) : null,
        'deleted_at': m.deletedAt?.toIso8601String(),
        'created_at': m.createdAt.toIso8601String(),
        'media_json': m.media.isNotEmpty ? jsonEncode(_mediaListToJson(m.media)) : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Met à jour le statut d'un message.
  static Future<void> updateStatus(String messageId, String status) async {
    final db = await _database();
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Supprime un message du cache local.
  static Future<void> remove(String messageId) async {
    final db = await _database();
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  /// Récupère tous les messages d'une conversation (du plus ancien au plus récent).
  static Future<List<Message>> getConv(String convId) async {
    final db = await _database();
    final rows = await db.query(
      'messages',
      where: 'conv_id = ?',
      whereArgs: [convId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Vide tout le cache (déconnexion).
  static Future<void> clear() async {
    final db = await _database();
    await db.delete('messages');
    // Les traductions sont du contenu de messages : les laisser derrière
    // laisserait des bribes de conversations du compte précédent sur l'appareil.
    await db.delete('traductions');
  }

  // --- Sérialisation helpers ---

  static Map<String, dynamic> _replyToJson(ReplyPreview r) => {
        'id': r.id,
        'senderId': r.senderId,
        'type': r.type,
        'content': r.content,
        'isDeleted': r.isDeleted,
      };

  static List<Map<String, dynamic>> _mediaListToJson(List<MessageMedia> media) =>
      media.map((m) => {
            'id': m.id,
            'url': m.url,
            'filename': m.filename,
            'mimeType': m.mimeType,
            'sizeBytes': m.sizeBytes,
            'durationMs': m.durationMs,
          }).toList();

  static Message _rowToMessage(Map<String, dynamic> row) {
    ReplyPreview? replyTo;
    if (row['reply_to_snapshot'] != null) {
      final j = jsonDecode(row['reply_to_snapshot'] as String) as Map<String, dynamic>;
      replyTo = ReplyPreview.fromJson(j);
    }

    List<MessageMedia> media = [];
    if (row['media_json'] != null) {
      final list = jsonDecode(row['media_json'] as String) as List;
      media = list.map((m) => MessageMedia.fromJson(m as Map<String, dynamic>)).toList();
    }

    return Message(
      id: row['id'] as String,
      convId: row['conv_id'] as String,
      senderId: row['sender_id'] as String,
      content: row['content'] as String?,
      type: row['type'] as String,
      status: row['status'] as String,
      replyToId: row['reply_to_id'] as String?,
      replyTo: replyTo,
      deletedAt: row['deleted_at'] != null
          ? DateTime.tryParse(row['deleted_at'] as String)
          : null,
      media: media,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
