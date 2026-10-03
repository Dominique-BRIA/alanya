import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/conversation.dart' show LastMessage;
import '../models/message.dart';
import '../services/e2ee/e2ee_media.dart';
import 'cache_clairs.dart';
import 'restauration_archive.dart';

/// Cache local des messages (offline-first).
///
/// Stocke les messages dans une base SQLite locale. Au chargement d'une
/// conversation, on affiche d'abord le cache (instantané), puis on synchronise
/// avec le serveur en arrière-plan pour récupérer les nouveaux messages.
/// Une traduction retenue : le texte, et la langue d'où il vient.
///
/// La LANGUE SOURCE accompagne le texte parce que la bulle l'affiche —
/// « traduit de l'anglais ». Sans elle, le fil dirait qu'un message a été
/// traduit sans dire de quoi, ce qui est précisément l'information utile quand
/// on relit une conversation à plusieurs langues.
///
/// `source` est nulle quand il n'y avait RIEN à traduire : le texte est alors
/// celui d'origine, et aucune mention ne doit s'afficher.
class TraductionLocale {
  const TraductionLocale({required this.texte, required this.source});
  final String texte;
  final String? source;
}

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
      version: 8,
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) await _creeTableTraductions(db);
        /*
         * v3 — LES MENTIONS `@`.
         *
         * Une colonne JSON sur `messages`, et non une table à part : une
         * mention ne se lit JAMAIS seule, toujours avec son message, et
         * `putConv` — qui efface puis réinsère la conversation — emporterait
         * de toute façon une table liée. C'est exactement l'inverse des
         * traductions, qui doivent survivre à ce cycle : d'où leur table
         * indépendante. Le cycle de vie de la donnée décide de sa forme.
         */
        if (ancienne < 3) {
          await db.execute('ALTER TABLE messages ADD COLUMN mentions_json TEXT');
        }
        /*
         * v4 — LE MESSAGE EST-IL CHIFFRÉ ?
         *
         * Sans cette colonne, un fil relu depuis le cache perdait l’indicateur,
         * et la bande « à partir d’ici, chiffré » ne savait plus où se placer
         * avant la réponse du serveur. Les lignes existantes valent 0 : elles
         * se corrigent au premier chargement réseau du fil.
         */
        if (ancienne < 4) {
          await db.execute(
              'ALTER TABLE messages ADD COLUMN chiffre INTEGER NOT NULL DEFAULT 0');
        }
        /*
         * v5 — L'EXPIRATION, ET UNE SEULE FORME DE DATE.
         *
         * `expires_at` : un message éphémère expiré doit quitter le cache. Tant
         * que `putConv` vidait le fil à chaque ouverture, il partait avec le
         * reste ; les textes chiffrés anciens étant désormais gardés, il
         * resterait lisible pour toujours.
         *
         * Les dates : voir `dateCache`. Les lignes écrites en heure du
         * téléphone sont réécrites en UTC, une par une — `DateTime.parse` sait
         * les relire, SQLite ne le sait pas de façon sûre.
         */
        if (ancienne < 5) {
          await db.execute('ALTER TABLE messages ADD COLUMN expires_at TEXT');
          final locales = await db.query('messages',
              columns: ['id', 'created_at', 'deleted_at'],
              where: "created_at NOT LIKE '%Z' OR deleted_at NOT LIKE '%Z'");
          for (final l in locales) {
            final supprime = l['deleted_at'] as String?;
            await db.update(
              'messages',
              {
                'created_at': dateNormalisee(l['created_at'] as String),
                'deleted_at': supprime == null ? null : dateNormalisee(supprime),
              },
              where: 'id = ?',
              whereArgs: [l['id']],
            );
          }
        }
        // v6 — les messages effacés de cet appareil : voir `_creeTableEffaces`.
        if (ancienne < 6) await _creeTableEffaces(db);
        /*
         * v7 — LA VUE UNIQUE, en un seul entier : 1 = vue unique, 2 = ouverte,
         * 4 = fichier effacé. Sans elle, un fil relu hors ligne montrerait
         * une photo à vue unique comme une photo ordinaire — et tenterait de
         * charger un média que le serveur refuse.
         */
        if (ancienne < 7) {
          await db.execute(
              'ALTER TABLE messages ADD COLUMN vue_unique INTEGER NOT NULL DEFAULT 0');
        }
        /*
         * v8 — LE MÉDIA CHIFFRÉ (cours, chapitre 23) : son descripteur, CLÉ
         * COMPRISE, en JSON. Le fichier du serveur est illisible ; sans cette
         * colonne, une photo reçue chiffrée ne se rouvrirait plus après la
         * consommation de son enveloppe.
         */
        if (ancienne < 8) {
          await db.execute('ALTER TABLE messages ADD COLUMN e2ee_media_json TEXT');
        }
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
            media_json TEXT,
            mentions_json TEXT,
            chiffre INTEGER NOT NULL DEFAULT 0,
            expires_at TEXT,
            vue_unique INTEGER NOT NULL DEFAULT 0,
            e2ee_media_json TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_conv ON messages(conv_id, created_at)',
        );
        await _creeTableTraductions(db);
        await _creeTableEffaces(db);
      },
    );
    return _db!;
  }

  /*
   * ═══ EFFACÉS ═══
   *
   * 🔴 LA MÉMOIRE D'UN EFFACEMENT, quand la ligne elle-même n'est plus là.
   *
   * « Supprimer pour moi » et l'expiration d'un éphémère RETIRENT la ligne du
   * cache. Mais l'archive chiffrée garde le texte, et la restauration tourne à
   * chaque lancement où l'archive a grossi : sans cette table, elle recréait
   * la ligne, et le message effacé ressortait en clair. Voir
   * `restauration_archive.dart`.
   *
   * ⚠️ UN IDENTIFIANT, RIEN DE PLUS : on retient QU'un message est parti, pas
   * ce qu'il disait.
   */
  static Future<void> _creeTableEffaces(Database db) => db.execute(
      'CREATE TABLE IF NOT EXISTS effaces (message_id TEXT PRIMARY KEY)');

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
  static Future<Map<String, TraductionLocale>> traductionsDe(
    String convId,
    String langueCible,
  ) async {
    final db = await _database();
    final rows = await db.query(
      'traductions',
      columns: ['message_id', 'texte', 'langue_source'],
      where: 'conv_id = ? AND langue_cible = ?',
      whereArgs: [convId, langueCible],
    );
    return {
      for (final r in rows)
        r['message_id'] as String: TraductionLocale(
          texte: r['texte'] as String,
          source: r['langue_source'] as String?,
        ),
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

  /// Range la dernière page du serveur pour une conversation.
  ///
  /// 🔴 NE VIDE PLUS LE FIL. Les textes déchiffrés plus anciens que la page, et
  /// ceux que le serveur rend sans contenu, sont gardés : ils n'existent nulle
  /// part ailleurs sur l'appareil. La règle est dans `cache_clairs.dart`.
  static Future<void> putConv(String convId, List<Message> messages) async {
    final db = await _database();
    final lignes = await db.query(
      'messages',
      columns: ['id', 'content', 'created_at', 'chiffre', 'e2ee_media_json'],
      where: 'conv_id = ?',
      whereArgs: [convId],
    );
    // 🔴 LE DESCRIPTEUR SURVIT AU RAFRAÎCHISSEMENT, comme le texte : le serveur
    // rend ce message sans lui, et l'écraser rendrait la photo impossible à
    // rouvrir, l'enveloppe étant déjà acquittée (chapitre 23).
    final descripteurs = <String, String>{
      for (final l in lignes)
        if (l['e2ee_media_json'] != null)
          l['id'] as String: l['e2ee_media_json'] as String,
    };
    final plan = planRemplacement(
      [
        for (final l in lignes)
          LigneCache(
            id: l['id'] as String,
            content: l['content'] as String?,
            createdAt: DateTime.parse(l['created_at'] as String),
            chiffre: (l['chiffre'] as int? ?? 0) == 1,
          ),
      ],
      messages,
    );

    final batch = db.batch();
    for (final id in plan.aEffacer) {
      batch.delete('messages', where: 'id = ?', whereArgs: [id]);
    }

    for (final m in messages) {
      batch.insert(
        'messages',
        {
          'id': m.id,
          'conv_id': convId,
          'sender_id': m.senderId,
          'content': plan.textes[m.id] ?? m.content,
          'type': m.type,
          'status': m.status,
          'reply_to_id': m.replyToId,
          'reply_to_snapshot':
              m.replyTo != null ? jsonEncode(_replyToJson(m.replyTo!)) : null,
          'deleted_at': m.deletedAt == null ? null : dateCache(m.deletedAt!),
          'created_at': dateCache(m.createdAt),
          'expires_at': m.expiresAt == null ? null : dateCache(m.expiresAt!),
          'media_json': m.media.isNotEmpty ? jsonEncode(_mediaListToJson(m.media)) : null,
          'mentions_json': m.mentions.isNotEmpty
              ? jsonEncode(m.mentions.map((x) => x.toJson()).toList())
              : null,
          'chiffre': m.chiffre ? 1 : 0,
          'vue_unique': bitsVueUnique(m),
          'e2ee_media_json': m.deletedAt != null
              ? null
              : m.mediaChiffre != null
                  ? jsonEncode(m.mediaChiffre!.toJson())
                  : descripteurs[m.id],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Ajoute ou met à jour un seul message (sans tout effacer).
  ///
  /// ⚠️ GARDE LE TEXTE DÉCHIFFRÉ : un message chiffré venu du serveur (une page
  /// plus ancienne, par exemple) arrive sans contenu. Voir `texteAEcrire`.
  static Future<void> upsert(Message m, String convId) async {
    final db = await _database();
    String? ancien;
    String? ancienDescripteur;
    if (((m.content ?? '').isEmpty || m.mediaChiffre == null) && m.deletedAt == null) {
      final l = await db.query('messages',
          columns: ['content', 'e2ee_media_json'],
          where: 'id = ?',
          whereArgs: [m.id],
          limit: 1);
      if (l.isNotEmpty) {
        ancien = l.first['content'] as String?;
        ancienDescripteur = l.first['e2ee_media_json'] as String?;
      }
    }
    await db.insert(
      'messages',
      {
        'id': m.id,
        'conv_id': convId,
        'sender_id': m.senderId,
        'content': texteAEcrire(m, ancien),
        'type': m.type,
        'status': m.status,
        'reply_to_id': m.replyToId,
        'reply_to_snapshot':
            m.replyTo != null ? jsonEncode(_replyToJson(m.replyTo!)) : null,
        'deleted_at': m.deletedAt == null ? null : dateCache(m.deletedAt!),
        'created_at': dateCache(m.createdAt),
        'expires_at': m.expiresAt == null ? null : dateCache(m.expiresAt!),
        'media_json': m.media.isNotEmpty ? jsonEncode(_mediaListToJson(m.media)) : null,
          'mentions_json': m.mentions.isNotEmpty
              ? jsonEncode(m.mentions.map((x) => x.toJson()).toList())
              : null,
          'chiffre': m.chiffre ? 1 : 0,
          'vue_unique': bitsVueUnique(m),
          'e2ee_media_json': m.deletedAt != null
              ? null
              : m.mediaChiffre != null
                  ? jsonEncode(m.mediaChiffre!.toJson())
                  : ancienDescripteur,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Le dernier message AVEC TEXTE de chacune de ces conversations.
  ///
  /// ⚠️ POUR LA LISTE DES CONVERSATIONS, fils chiffrés : le serveur n'a pas
  /// leur texte, l'appareil si — voir `dernier_message_local.dart`. Une seule
  /// requête pour toutes les conversations, pas une par ligne de la liste.
  ///
  /// 🐛 ELLE LISAIT TOUT : chaque message texte de chaque fil chiffré, trié,
  /// pour n'en garder qu'un par fil — et la liste la relance toutes les cinq
  /// secondes. Désormais une ligne par fil.
  ///
  /// ⚠️ `MAX(created_at)` AVEC DES COLONNES NUES : SQLite garantit que ces
  /// colonnes viennent de la ligne qui porte le maximum (documenté, « bare
  /// columns in aggregate queries », depuis la 3.7.11 ; Android 7 embarque la
  /// 3.9). Ce n'est juste que parce que toutes les dates ont la même forme —
  /// voir `dateCache`.
  static Future<Map<String, LastMessage>> derniersTextes(Iterable<String> convIds) async {
    final ids = convIds.toList();
    if (ids.isEmpty) return {};
    final db = await _database();
    await _purgerExpires(db);
    final lignes = await db.rawQuery(
      'SELECT id, conv_id, sender_id, content, type, MAX(created_at) AS created_at '
      'FROM messages '
      'WHERE conv_id IN (${List.filled(ids.length, '?').join(',')}) '
      "AND content IS NOT NULL AND content != '' AND deleted_at IS NULL "
      'GROUP BY conv_id',
      ids,
    );
    return {
      for (final l in lignes)
        l['conv_id'] as String: LastMessage(
          id: l['id'] as String,
          content: l['content'] as String?,
          type: l['type'] as String,
          senderId: l['sender_id'] as String,
          createdAt: DateTime.parse(l['created_at'] as String),
        ),
    };
  }

  /// Retire du cache les messages éphémères arrivés à échéance.
  ///
  /// ⚠️ LE SERVEUR NE PRÉVIENT PAS : sa purge est silencieuse. Seule la date
  /// d'expiration, rangée avec le message, permet de l'oublier ici.
  ///
  /// ⚠️ LIMITE : un message chiffré seulement RELEVÉ (fil jamais ouvert depuis)
  /// n'a pas encore sa date — l'enveloppe ne la porte pas. Il la reçoit à
  /// l'ouverture du fil, qui écrit la page du serveur.
  static Future<void> _purgerExpires(Database db) async {
    final maintenant = dateCache(DateTime.now());
    // ⚠️ RETENU AVANT D'ÊTRE RETIRÉ : l'archive ne connaît pas l'expiration, et
    // la restauration suivante recréerait l'éphémère. Voir `_creeTableEffaces`.
    await db.rawInsert(
      'INSERT OR IGNORE INTO effaces (message_id) '
      'SELECT id FROM messages WHERE expires_at IS NOT NULL AND expires_at <= ?',
      [maintenant],
    );
    await db.delete(
      'messages',
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [maintenant],
    );
  }

  /// Range le texte d'un message chiffré qu'on vient de relever — dans SON fil.
  ///
  /// 🔴 C'EST LA SEULE COPIE DE CE TEXTE SUR L'APPAREIL. La relève va acquitter
  /// l'enveloppe, et le cliquet a déjà consommé la clé : ce qui n'est pas rangé
  /// ici est perdu.
  ///
  /// ⚠️ UNE MISE À JOUR D'ABORD, pas un `upsert` : si la ligne existe déjà
  /// (elle est arrivée par le temps réel), on n'en change QUE le texte. Un
  /// `upsert` la remplacerait entière et perdrait ce que la relève ne connaît
  /// pas — statut, réponse citée, mentions.
  ///
  /// ⚠️ SINON UNE LIGNE MINIMALE, qui suffit : à l'ouverture du fil, la liste du
  /// serveur arrive sans texte et `_garderLeClairConnu` recolle celui-ci.
  /// Rend `true` si le texte a bien été rangé, `false` s'il a été écarté
  /// (ligne d'un autre expéditeur ou d'un autre fil, supprimée, ou effacée) —
  /// et alors il ne doit pas non plus partir dans l'archive.
  static Future<bool> rangeTexteDechiffre({
    required String id,
    required String convId,
    required String expediteurId,
    required String texte,
    required DateTime quand,
    DescripteurMedia? media,
  }) async {
    final mediaJson = media == null ? null : jsonEncode(media.toJson());
    final db = await _database();
    /*
     * 🐛 UN MESSAGE SUPPRIMÉ RETROUVAIT SON TEXTE. L'enveloppe peut arriver
     * APRÈS la suppression — destinataire hors ligne, relève tardive — et la
     * mise à jour visait la ligne par son seul identifiant : le clair d'un
     * message supprimé pour tous revenait s'y loger.
     */
    final modifiees = await db.update(
      'messages',
      // Un texte venu d’une enveloppe : le message est chiffré par définition.
      {
        'content': texte,
        'chiffre': 1,
        if (mediaJson != null) 'e2ee_media_json': mediaJson,
      },
      /*
       * ⚠️ `sender_id` ET `conv_id` AUSSI : l'identifiant vient du serveur,
       * hors du chiffré, alors que l'expéditeur est sûr (sa session a
       * déchiffré). Une ligne d'un autre expéditeur ou d'un autre fil n'est pas
       * touchée — et l'insertion qui suit est alors écartée par la clé.
       */
      where: 'id = ? AND deleted_at IS NULL AND sender_id = ? AND conv_id = ?',
      whereArgs: [id, expediteurId, convId],
    );
    if (modifiees > 0) return true;
    /*
     * ⚠️ `OR IGNORE` écarte une ligne déjà là (supprimée pour tous, ou d'un
     * autre expéditeur) ; le `NOT EXISTS` écarte une ligne effacée de cet
     * appareil.
     */
    // Ligne complète pour un média : type déduit du vrai type du fichier, et
    // ligne de média reconstruite — le fil peut l'afficher avant que le
    // serveur ait rendu la sienne.
    await db.rawInsert(
      'INSERT OR IGNORE INTO messages '
      '(id, conv_id, sender_id, content, type, status, created_at, chiffre, media_json, e2ee_media_json) '
      "SELECT ?, ?, ?, ?, ?, 'DELIVERED', ?, 1, ?, ? "
      'WHERE NOT EXISTS (SELECT 1 FROM effaces WHERE message_id = ?)',
      [
        id,
        convId,
        expediteurId,
        texte,
        typeMessagePour(media),
        dateCache(quand),
        media == null ? null : jsonEncode([ligneMediaChiffre(media)]),
        mediaJson,
        id,
      ],
    );
    // L'insertion a-t-elle eu lieu ? `rawInsert` ne le dit pas de façon sûre
    // avec `OR IGNORE` : on relit.
    final l = await db.query('messages',
        columns: ['content', 'sender_id', 'e2ee_media_json'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    return l.isNotEmpty &&
        l.first['content'] == texte &&
        l.first['sender_id'] == expediteurId &&
        (mediaJson == null || l.first['e2ee_media_json'] == mediaJson);
  }

  /// Range un message venu de l'archive chiffrée — sans rien défaire.
  ///
  /// ⚠️ PAS UN `upsert`. La règle, et le défaut qu'elle corrige, sont dans
  /// `restauration_archive.dart` : une ligne existante ne reçoit au plus que
  /// son texte manquant, une ligne supprimée ou effacée ne bouge pas.
  static Future<void> restaurerDepuisArchive({
    required String id,
    required String convId,
    required String expediteurId,
    required String texte,
    required DateTime quand,
    DescripteurMedia? media,
  }) async {
    final db = await _database();
    final efface = (await db.query('effaces',
            where: 'message_id = ?', whereArgs: [id], limit: 1))
        .isNotEmpty;
    final l = await db.query('messages',
        columns: ['content', 'deleted_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    final geste = gesteRestauration(
      efface: efface,
      ligne: l.isEmpty
          ? null
          : (texte: l.first['content'] as String?, supprime: l.first['deleted_at'] != null),
    );
    switch (geste) {
      case GesteRestauration.rien:
        return;
      case GesteRestauration.completerTexte:
        await db.update(
          'messages',
          {'content': texte, 'chiffre': 1},
          where: "id = ? AND deleted_at IS NULL AND (content IS NULL OR content = '')",
          whereArgs: [id],
        );
      case GesteRestauration.inserer:
        await db.insert(
          'messages',
          {
            'id': id,
            'conv_id': convId,
            'sender_id': expediteurId,
            'content': texte,
            'type': 'TEXT',
            'status': 'SENT',
            'created_at': dateCache(quand),
            'chiffre': 1,
            if (media != null) ...{
              'type': typeMessagePour(media),
              'media_json': jsonEncode([ligneMediaChiffre(media)]),
              'e2ee_media_json': jsonEncode(media.toJson()),
            },
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
    }
    /*
     * LE DESCRIPTEUR SE COMPLÈTE À PART DU TEXTE. Une ligne qui a déjà son
     * texte — légende relevée, ou vide — peut encore attendre sa clé : c'est
     * le cas d'un nouveau téléphone qui a reçu la liste du serveur avant
     * l'archive. Jamais sur une ligne supprimée ou effacée d'ici.
     */
    if (media != null && !efface) {
      await db.update(
        'messages',
        {'e2ee_media_json': jsonEncode(media.toJson()), 'chiffre': 1},
        where: 'id = ? AND deleted_at IS NULL AND e2ee_media_json IS NULL',
        whereArgs: [id],
      );
    }
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

  /// Reporte dans le cache l'événement `message_deleted` du serveur.
  ///
  /// 🔴 SANS LUI, UN TEXTE SUPPRIMÉ RESTAIT SUR L'APPAREIL. Seul l'écran de
  /// conversation ouvert réagissait, et seulement à l'écran. Tant que `putConv`
  /// vidait le fil à chaque ouverture, le défaut se corrigeait tout seul ;
  /// maintenant que les textes chiffrés anciens sont gardés, il ne se
  /// corrigerait plus jamais.
  ///
  /// [scope] `me` : le message disparaît pour nous seuls → la ligne part.
  /// Sinon (`everyone`) : la ligne reste, marquée supprimée, sans texte ni média
  /// — comme le serveur la rend. Sa traduction part dans les deux cas.
  static Future<void> appliquerSuppression(String messageId, String scope) async {
    final db = await _database();
    // ⚠️ Retenu, pour que l'archive ne le fasse pas revenir : voir `_creeTableEffaces`.
    await db.insert('effaces', {'message_id': messageId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (scope == 'me') {
      await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
    } else {
      await db.update(
        'messages',
        {
          'content': null,
          'media_json': null,
          'deleted_at': dateCache(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    }
    await db.delete('traductions', where: 'message_id = ?', whereArgs: [messageId]);
  }

  /// Récupère tous les messages d'une conversation (du plus ancien au plus récent).
  static Future<List<Message>> getConv(String convId) async {
    final db = await _database();
    await _purgerExpires(db);
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
    await db.delete('effaces');
  }

  // --- Sérialisation helpers ---

  /// L'état de vue unique en un entier (voir la migration v7).
  static int bitsVueUnique(Message m) => !m.vueUnique
      ? 0
      : 1 | (m.vueUniqueOuverte ? 2 : 0) | (m.vueUniqueEffacee ? 4 : 0);

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
            if (m.chiffre) 'chiffre': true,
          }).toList();

  /// Un descripteur relu ; illisible = absent, jamais une exception qui
  /// ferait tomber tout le fil.
  static DescripteurMedia? _descripteur(String? json) {
    if (json == null) return null;
    try {
      return DescripteurMedia.depuisJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }


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

    // ⚠️ La colonne n'existe pas dans une base restée en v2 le temps d'une
    // migration : `row['mentions_json']` vaut alors `null`, et le message
    // s'affiche sans mise en évidence plutôt que de faire échouer la lecture.
    List<MentionMessage> mentions = const [];
    if (row['mentions_json'] != null) {
      final list = jsonDecode(row['mentions_json'] as String) as List;
      mentions = list
          .whereType<Map<String, dynamic>>()
          .map(MentionMessage.fromJson)
          .toList();
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
      expiresAt: row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'] as String)
          : null,
      media: media,
      createdAt: DateTime.parse(row['created_at'] as String),
      mentions: mentions,
      chiffre: row['chiffre'] == 1,
      mediaChiffre: _descripteur(row['e2ee_media_json'] as String?),
      // `?? 0` : base encore en v6 le temps de la migration.
      vueUnique: ((row['vue_unique'] as int?) ?? 0) & 1 != 0,
      vueUniqueOuverte: ((row['vue_unique'] as int?) ?? 0) & 2 != 0,
      vueUniqueEffacee: ((row['vue_unique'] as int?) ?? 0) & 4 != 0,
    );
  }
}
