import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/call_record.dart';

/// Cache local de l'historique des appels (offline-first).
class CallCache {
  CallCache._();
  static Database? _db;

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'alanya_calls.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE calls (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            started_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_call_started ON calls(started_at DESC)',
        );
      },
    );
    return _db!;
  }

  static Future<void> putAll(List<CallRecord> calls) async {
    final db = await _database();
    final batch = db.batch();
    batch.delete('calls');
    for (final c in calls) {
      batch.insert('calls', {
        'id': c.id,
        'payload': jsonEncode(_toJson(c)),
        'started_at': c.startedAt.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<CallRecord>> getAll() async {
    try {
      final db = await _database();
      final rows = await db.query('calls', orderBy: 'started_at DESC', limit: 200);
      return rows
          .map((r) {
            try {
              return CallRecord.fromJson(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<CallRecord>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      final db = await _database();
      await db.delete('calls');
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(CallRecord c) => {
        'id': c.id,
        'convId': c.convId,
        'type': c.type,
        'status': c.status,
        'isOutgoing': c.isOutgoing,
        'isGroup': c.isGroup,
        'peerName': c.peerName,
        'peerNumber': c.peerNumber,
        'peerAvatarUrl': c.peerAvatarUrl,
        'participantCount': c.participantCount,
        'startedAt': c.startedAt.toIso8601String(),
        'answeredAt': c.answeredAt?.toIso8601String(),
        'endedAt': c.endedAt?.toIso8601String(),
        'durationSec': c.durationSec,
      };
}
