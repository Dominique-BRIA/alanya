class MessageMedia {
  final String id;
  final String url; // chemin servi par /api/media/:id
  final String? filename;
  final String mimeType;
  final int? sizeBytes;
  final int? durationMs;

  MessageMedia({
    required this.id,
    required this.url,
    required this.mimeType,
    this.filename,
    this.sizeBytes,
    this.durationMs,
  });

  bool get isImage => mimeType.startsWith("image/");

  factory MessageMedia.fromJson(Map<String, dynamic> j) => MessageMedia(
        id: j["id"] as String,
        url: j["url"] as String,
        filename: j["filename"] as String?,
        mimeType: j["mimeType"] as String,
        sizeBytes: (j["sizeBytes"] as num?)?.toInt(),
        durationMs: (j["durationMs"] as num?)?.toInt(),
      );
}

/// Snapshot d'un message cité (réponse). Permet d'afficher l'aperçu du message
/// original côté UI sans dépendre du chargement local de l'historique.
class ReplyPreview {
  final String id;
  final String senderId;
  final String type;
  final String? content;
  final bool isDeleted;

  ReplyPreview({
    required this.id,
    required this.senderId,
    required this.type,
    this.content,
    this.isDeleted = false,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: j["id"] as String,
        senderId: j["senderId"] as String,
        type: j["type"] as String? ?? "TEXT",
        content: j["content"] as String?,
        isDeleted: j["isDeleted"] as bool? ?? false,
      );
}

class Message {
  final String id;
  final String convId;
  final String senderId;
  final String? content;
  final String type; // TEXT, IMAGE, FILE, AUDIO, VIDEO
  final String status; // SENT, DELIVERED, READ
  final String? replyToId;
  final ReplyPreview? replyTo; // snapshot du message cité (venant du backend)
  final DateTime? deletedAt; // non-null = message supprimé pour tous
  final List<MessageMedia> media;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.convId,
    required this.senderId,
    required this.content,
    required this.type,
    required this.status,
    required this.replyToId,
    required this.media,
    required this.createdAt,
    this.deletedAt,
    this.replyTo,
  });

  /// Vrai si le message a été supprimé pour tout le monde.
  bool get isDeleted => deletedAt != null;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j["id"] as String,
        convId: j["convId"] as String,
        senderId: j["senderId"] as String,
        content: j["content"] as String?,
        type: j["type"] as String,
        status: (j["status"] as String?) ?? "SENT",
        replyToId: j["replyToId"] as String?,
        replyTo: j["replyTo"] != null
            ? ReplyPreview.fromJson(j["replyTo"] as Map<String, dynamic>)
            : null,
        deletedAt: j["deletedAt"] != null ? DateTime.tryParse(j["deletedAt"] as String) : null,
        media: ((j["media"] as List?) ?? [])
            .map((m) => MessageMedia.fromJson(m as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j["createdAt"] as String),
      );
}
