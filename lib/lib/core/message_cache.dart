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
      version: 1,
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
      },
    );
    return _db!;
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
