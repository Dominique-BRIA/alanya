class StatusItem {
  final String id;
  final String type; // TEXT, IMAGE, VIDEO
  final String? text;
  final String? mediaUrl;
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

  String get displayName => pseudo ?? publicNumber;

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

  factory StatusFeed.fromJson(Map<String, dynamic> j) => StatusFeed(
        me: j["me"] == null ? null : StatusGroup.fromJson(j["me"] as Map<String, dynamic>),
        others: ((j["others"] as List?) ?? [])
            .map((g) => StatusGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
      );
}
