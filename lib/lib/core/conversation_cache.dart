import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/conversation.dart';

/// Cache local des conversations (offline-first).
///
/// Stocke la liste des conversations dans une base SQLite locale. Au démarrage
/// de HomeScreen on affiche instantanément le cache, puis on synchronise en
/// arrière-plan avec le serveur. Si le réseau est indisponible, l'utilisateur
/// voit ses conversations quand même (comportement WhatsApp).
class ConversationCache {
  ConversationCache._();
  static Database? _db;

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'alanya_conversations.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_conv_updated ON conversations(updated_at DESC)',
        );
      },
    );
    return _db!;
  }

  /// Remplace le cache par la liste actuelle (mise à jour après sync réseau).
  static Future<void> putAll(List<Conversation> convs) async {
    final db = await _database();
    final batch = db.batch();
    // On garde une approche "replace all" : simple et cohérente.
    // Les conversations supprimées côté serveur disparaissent bien du cache.
    batch.delete('conversations');
    for (final c in convs) {
      batch.insert('conversations', {
        'id': c.id,
        'payload': jsonEncode(_toJson(c)),
        'updated_at': c.updatedAt.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Récupère toutes les conversations en cache (ordonnées récentes d'abord).
  static Future<List<Conversation>> getAll() async {
    try {
      final db = await _database();
      final rows = await db.query(
        'conversations',
        orderBy: 'updated_at DESC',
      );
      return rows
          .map((r) {
            try {
              return Conversation.fromJson(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<Conversation>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Vide tout le cache (à appeler au logout).
  static Future<void> clear() async {
    try {
      final db = await _database();
      await db.delete('conversations');
    } catch (_) {}
  }

  /// Sérialise une Conversation en JSON compatible avec Conversation.fromJson.
  static Map<String, dynamic> _toJson(Conversation c) => {
        'id': c.id,
        'isGroup': c.isGroup,
        'title': c.title,
        'avatarUrl': c.avatarUrl,
        'members': c.members
            .map((m) => {
                  'id': m.id,
                  'pseudo': m.pseudo,
                  'publicNumber': m.publicNumber,
                })
            .toList(),
        'lastMessage': c.lastMessage == null
            ? null
            : {
                'id': c.lastMessage!.id,
                'content': c.lastMessage!.content,
                'type': c.lastMessage!.type,
                'senderId': c.lastMessage!.senderId,
                'createdAt': c.lastMessage!.createdAt.toIso8601String(),
              },
        'unread': c.unread,
        'updatedAt': c.updatedAt.toIso8601String(),
      };
}
