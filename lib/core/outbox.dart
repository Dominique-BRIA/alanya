import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../features/chat/chat_repository.dart';
import 'connectivity_service.dart';
import 'message_cache.dart';

/// Un message en attente d'envoi.
class OutboxEntry {
  final String tempId;
  final String convId;
  final String content;
  final String? replyToId;
  final DateTime createdAt;
  final int attempts;

  OutboxEntry({
    required this.tempId,
    required this.convId,
    required this.content,
    required this.replyToId,
    required this.createdAt,
    required this.attempts,
  });

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'convId': convId,
        'content': content,
        'replyToId': replyToId,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
        tempId: j['tempId'] as String,
        convId: j['convId'] as String,
        content: j['content'] as String,
        replyToId: j['replyToId'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        attempts: (j['attempts'] as int?) ?? 0,
      );
}

/// File d'attente des messages TEXTE envoyés offline.
///
/// - `enqueue()` : sauvegarde localement + retourne immédiatement (UI fluide)
/// - `flush()` : appelée automatiquement quand la connectivité revient,
///   envoie les messages un par un dans l'ordre chronologique
/// - Persistée en SQLite → survit à un kill de l'app
///
/// Limitation actuelle : uniquement les messages TEXTE. Les médias (image,
/// audio, vidéo) nécessitent un upload multipart qui n'est pas rejouable
/// simplement — on garde le comportement actuel "erreur si offline".
class Outbox extends ChangeNotifier {
  Outbox(this._chat, this._conn) {
    _conn.addListener(_onConnChange);
    _load();
  }

  final ChatRepository _chat;
  final ConnectivityService _conn;
  Database? _db;
  List<OutboxEntry> _entries = [];
  bool _flushing = false;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  /// Nombre de messages en attente pour une conversation donnée.
  int pendingCountFor(String convId) =>
      _entries.where((e) => e.convId == convId).length;

  /// Vrai si le message [tempId] est en attente d'envoi (pour afficher une
  /// icône horloge à côté).
  bool isPending(String tempId) => _entries.any((e) => e.tempId == tempId);

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'alanya_outbox.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox (
            temp_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> _load() async {
    try {
      final db = await _database();
      final rows = await db.query('outbox', orderBy: 'created_at ASC');
      _entries = rows
          .map((r) {
            try {
              return OutboxEntry.fromJson(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<OutboxEntry>()
          .toList();
      notifyListeners();
      // Tentative de flush au démarrage si on est déjà online.
      if (_conn.isOnline) unawaited(flush());
    } catch (_) {}
  }

  Future<void> _persist(OutboxEntry e) async {
    try {
      final db = await _database();
      await db.insert(
        'outbox',
        {
          'temp_id': e.tempId,
          'payload': jsonEncode(e.toJson()),
          'created_at': e.createdAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> _remove(String tempId) async {
    try {
      final db = await _database();
      await db.delete('outbox', where: 'temp_id = ?', whereArgs: [tempId]);
    } catch (_) {}
  }

  /// Empile un message pour envoi ultérieur. Retourne immédiatement.
  /// Si on est online, tente le flush juste après (transparent pour l'utilisateur).
  Future<void> enqueue({
    required String tempId,
    required String convId,
    required String content,
    String? replyToId,
  }) async {
    final entry = OutboxEntry(
      tempId: tempId,
      convId: convId,
      content: content,
      replyToId: replyToId,
      createdAt: DateTime.now(),
      attempts: 0,
    );
    _entries.add(entry);
    await _persist(entry);
    notifyListeners();
    if (_conn.isOnline) unawaited(flush());
  }

  void _onConnChange() {
    if (_conn.isOnline && _entries.isNotEmpty && !_flushing) {
      unawaited(flush());
    }
  }

  /// Tente d'envoyer tous les messages en attente. Sûr d'être appelé en
  /// parallèle : le drapeau [_flushing] évite les doubles envois.
  Future<void> flush() async {
    if (_flushing || _entries.isEmpty) return;
    _flushing = true;
    try {
      // Copie pour éviter les problèmes de modification pendant l'itération.
      final toSend = List<OutboxEntry>.from(_entries);
      for (final entry in toSend) {
        if (!_conn.isOnline) break; // stop si le réseau retombe
        try {
          final sent = await _chat.sendText(
            entry.convId,
            entry.content,
            replyToId: entry.replyToId,
          );
          // Succès : retire de la file, met le vrai message en cache.
          _entries.removeWhere((e) => e.tempId == entry.tempId);
          await _remove(entry.tempId);
          await MessageCache.upsert(sent, entry.convId);
          notifyListeners();
        } catch (_) {
          // Échec : incrémente les tentatives mais on garde en file.
          // Abandonne après 5 tentatives pour ne pas boucler à l'infini.
          final idx = _entries.indexWhere((e) => e.tempId == entry.tempId);
          if (idx >= 0) {
            final old = _entries[idx];
            if (old.attempts >= 4) {
              _entries.removeAt(idx);
              await _remove(old.tempId);
            } else {
              final updated = OutboxEntry(
                tempId: old.tempId,
                convId: old.convId,
                content: old.content,
                replyToId: old.replyToId,
                createdAt: old.createdAt,
                attempts: old.attempts + 1,
              );
              _entries[idx] = updated;
              await _persist(updated);
            }
            notifyListeners();
          }
          break; // stop et on retentera plus tard
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> clear() async {
    _entries.clear();
    try {
      final db = await _database();
      await db.delete('outbox');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _conn.removeListener(_onConnChange);
    super.dispose();
  }
}
