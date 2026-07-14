import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/contact.dart';

/// Cache local du répertoire de contacts (offline-first).
class ContactCache {
  ContactCache._();
  static Database? _db;

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'alanya_contacts.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE contacts (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            display_name TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_contact_name ON contacts(display_name COLLATE NOCASE)',
        );
      },
    );
    return _db!;
  }

  static Future<void> putAll(List<Contact> contacts) async {
    final db = await _database();
    final batch = db.batch();
    batch.delete('contacts');
    for (final c in contacts) {
      batch.insert('contacts', {
        'id': c.id,
        'payload': jsonEncode(_toJson(c)),
        'display_name': c.displayName,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Contact>> getAll() async {
    try {
      final db = await _database();
      final rows = await db.query('contacts', orderBy: 'display_name COLLATE NOCASE');
      return rows
          .map((r) {
            try {
              return Contact.fromJson(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<Contact>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      final db = await _database();
      await db.delete('contacts');
    } catch (_) {}
  }

  /// Format compatible avec Contact.fromJson (qui attend un champ "user").
  static Map<String, dynamic> _toJson(Contact c) => {
        'id': c.id,
        'alias': c.alias,
        'isBlocked': c.isBlocked,
        'user': {
          'id': c.userId,
          'publicNumber': c.publicNumber,
          'pseudo': c.pseudo,
          'avatarUrl': c.avatarUrl,
        },
      };
}
