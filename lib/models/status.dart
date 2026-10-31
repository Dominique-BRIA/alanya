import '../core/alanya_id_formatter.dart';
import '../core/noms_donnes.dart';

class StatusItem {
  final String id;
  final String type; // TEXT, IMAGE, VIDEO, AUDIO (01/11/2026)
  final String? text;
  final String? mediaUrl;

  /// Durée d'un statut audio ou vidéo, en millisecondes (01/11/2026).
  final int? mediaDurationMs;

  /// L'ai-je aimé ? (01/11/2026)
  final bool likedByMe;

  /// Nombre de « J'aime » — connu de l'auteur seul.
  final int? likesCount;
  final String? bgColor; // #RRGGBB / #AARRGGBB
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewed;
  final int viewsCount;

  StatusItem({
    required this.id,
    required this.type,
    required this.text,
    required this.mediaUrl,
    required this.bgColor,
    required this.createdAt,
    required this.expiresAt,
    required this.viewed,
    required this.viewsCount,
    this.mediaDurationMs,
    this.likedByMe = false,
    this.likesCount,
  });

  factory StatusItem.fromJson(Map<String, dynamic> j) => StatusItem(
        id: j["id"] as String,
        type: j["type"] as String,
        text: j["text"] as String?,
        mediaUrl: j["mediaUrl"] as String?,
        bgColor: j["bgColor"] as String?,
        createdAt: DateTime.parse(j["createdAt"] as String),
        expiresAt: DateTime.parse(j["expiresAt"] as String),
        viewed: (j["viewed"] as bool?) ?? false,
        viewsCount: (j["viewsCount"] as num?)?.toInt() ?? 0,
        mediaDurationMs: (j["mediaDurationMs"] as num?)?.toInt(),
        likedByMe: (j["likedByMe"] as bool?) ?? false,
        likesCount: (j["likesCount"] as num?)?.toInt(),
      );
}

class StatusGroup {
  final String userId;
  final String? pseudo;
  final String? avatarUrl;
  final String publicNumber;
  final bool hasUnviewed;
  final List<StatusItem> statuses;

  StatusGroup({
    required this.userId,
    required this.pseudo,
    required this.avatarUrl,
    required this.publicNumber,
    required this.hasUnviewed,
    required this.statuses,
  });

  /// Repli FORMATE — voir la note detaillee sur `Contact.displayName`.
  ///
  /// Le nom que J'AI donné à cette personne passe devant (`NomsDonnes`).
  String get displayName =>
      NomsDonnes.nomPour(userId, pseudo ?? formatAlanyaId(publicNumber));

  factory StatusGroup.fromJson(Map<String, dynamic> j) => StatusGroup(
        userId: j["userId"] as String,
        pseudo: j["pseudo"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
        publicNumber: j["publicNumber"] as String,
        hasUnviewed: (j["hasUnviewed"] as bool?) ?? false,
        statuses: ((j["statuses"] as List?) ?? [])
            .map((s) => StatusItem.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class StatusFeed {
  final StatusGroup? me;
  final List<StatusGroup> others;
  StatusFeed({required this.me, required this.others});

  /// Le même fil sans les statuts expirés — pour une copie gardée sur le
  /// téléphone, que le temps a pu dépasser. Une personne sans statut restant
  /// disparaît de la liste ; « Mon statut » reste, vide.
  StatusFeed sansExpires([DateTime? maintenant]) {
    final t = maintenant ?? DateTime.now();
    StatusGroup garder(StatusGroup g) => StatusGroup(
          userId: g.userId,
          pseudo: g.pseudo,
          avatarUrl: g.avatarUrl,
          publicNumber: g.publicNumber,
          hasUnviewed: g.hasUnviewed,
          statuses: [for (final s in g.statuses) if (s.expiresAt.isAfter(t)) s],
        );
    final moi = me == null ? null : garder(me!);
    return StatusFeed(
      me: moi == null || moi.statuses.isEmpty ? null : moi,
      others: [
        for (final g in others.map(garder))
          if (g.statuses.isNotEmpty) g,
      ],
    );
  }

  factory StatusFeed.fromJson(Map<String, dynamic> j) => StatusFeed(
        me: j["me"] == null
            ? null
            : StatusGroup.fromJson(j["me"] as Map<String, dynamic>),
        others: ((j["others"] as List?) ?? [])
            .map((g) => StatusGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
      );
}
