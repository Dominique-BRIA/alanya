class LastMessage {
  final String id;
  final String? content;
  final String type;
  final String senderId;
  final DateTime createdAt;

  LastMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.senderId,
    required this.createdAt,
  });

  factory LastMessage.fromJson(Map<String, dynamic> j) => LastMessage(
        id: j["id"] as String,
        content: j["content"] as String?,
        type: j["type"] as String,
        senderId: j["senderId"] as String,
        createdAt: DateTime.parse(j["createdAt"] as String),
      );
}

class ConvMember {
  final String id;
  final String? pseudo;
  final String publicNumber;
  final int isOnline;
  final DateTime? lastSeen;

  ConvMember({
    required this.id,
    required this.pseudo,
    required this.publicNumber,
    this.isOnline = 0,
    this.lastSeen,
  });

  String get displayName => pseudo ?? publicNumber;
  bool get online => isOnline == 1;

  /// "en ligne" ou "vu il y a 5 min"
  String get onlineStatus {
    if (online) return "en ligne";
    if (lastSeen == null) return "";
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inMinutes < 1) return "vu à l'instant";
    if (diff.inMinutes < 60) return "vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "vu il y a ${diff.inHours}h";
    return "vu il y a ${diff.inDays}j";
  }

  factory ConvMember.fromJson(Map<String, dynamic> j) => ConvMember(
        id: j["id"] as String,
        pseudo: j["pseudo"] as String?,
        publicNumber: j["publicNumber"] as String,
        isOnline: (j["isOnline"] as num?)?.toInt() ?? 0,
        lastSeen: j["lastSeen"] != null ? DateTime.tryParse(j["lastSeen"] as String) : null,
      );
}

class Conversation {
  final String id;
  final bool isGroup;
  final String? title;
  final String? avatarUrl;
  final List<ConvMember> members;
  final LastMessage? lastMessage;
  final int unread;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isArchived;

  Conversation({
    required this.id,
    required this.isGroup,
    required this.title,
    required this.avatarUrl,
    required this.members,
    required this.lastMessage,
    required this.unread,
    required this.updatedAt,
    this.isPinned = false,
    this.isArchived = false,
  });

  Map<String, String> get memberNames => {
        for (final m in members) m.id: m.displayName,
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j["id"] as String,
        isGroup: j["isGroup"] as bool,
        title: j["title"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
        members: ((j["members"] as List?) ?? [])
            .map((m) => ConvMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        lastMessage: j["lastMessage"] == null
            ? null
            : LastMessage.fromJson(j["lastMessage"] as Map<String, dynamic>),
        unread: (j["unread"] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(j["updatedAt"] as String),
        isPinned: (j["isPinned"] as bool?) ?? false,
        isArchived: (j["isArchived"] as bool?) ?? false,
      );
}
