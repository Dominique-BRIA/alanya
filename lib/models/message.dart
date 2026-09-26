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

/// Réaction emoji d'un utilisateur sur un message.
class MessageReaction {
  final String userId;
  final String emoji;

  MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        userId: j["userId"] as String,
        emoji: j["emoji"] as String,
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

/// Le statut qu'un message cite, tel que le serveur l'a RECOPIÉ à l'envoi.
///
/// 🔴 C'EST UN INSTANTANÉ, PAS UNE RÉFÉRENCE. Un statut vit 24 h puis est
/// purgé : une citation qui pointerait vers lui deviendrait un trou dans la
/// conversation le lendemain. L'aperçu reste donc lisible indéfiniment, même
/// une fois le statut disparu — et c'est aussi pourquoi le client ne peut pas
/// le fabriquer : seul le serveur le remplit.
class StatutCite {
  final String statusId;
  final String authorId;

  /// TEXT, IMAGE ou VIDEO — celui du statut, pas celui du message.
  final String type;
  final String? text;
  final String? mediaUrl;
  final String? bgColor;

  StatutCite({
    required this.statusId,
    required this.authorId,
    required this.type,
    this.text,
    this.mediaUrl,
    this.bgColor,
  });

  factory StatutCite.fromJson(Map<String, dynamic> j) => StatutCite(
        statusId: j["statusId"] as String,
        authorId: j["authorId"] as String,
        type: j["type"] as String? ?? "TEXT",
        text: j["text"] as String?,
        mediaUrl: j["mediaUrl"] as String?,
        bgColor: j["bgColor"] as String?,
      );

  /// Ce que la citation affiche quand le statut n'a pas de texte.
  String get apercu {
    final t = text?.trim();
    if (t != null && t.isNotEmpty) return t;
    return switch (type) {
      "IMAGE" => "Photo",
      "VIDEO" => "Vidéo",
      _ => "Statut",
    };
  }
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
  final DateTime? editedAt; // non-null = message modifié (affiche « modifié »)
  final DateTime?
      expiresAt; // non-null = message éphémère (disparaît à échéance)
  final List<MessageMedia> media;
  final DateTime createdAt;
  // Réactions emoji — mutable : mises à jour en place à la réception des events
  // WS `reaction` (puis setState côté écran). Brutes { userId, emoji }.
  List<MessageReaction> reactions;
  // Favori (étoile) pour MOI — mutable : basculé en place au tap.
  bool starred;

  /// LES MENTIONS `@` DU MESSAGE — groupes seulement.
  ///
  /// 🔴 LE TEXTE PORTE « @Dominique » EN CLAIR ; cette liste dit QUEL compte
  /// est visé. Sans elle, mettre en évidence reviendrait à chercher un pseudo
  /// dans une phrase, et notifier reviendrait à le deviner — ce qui échoue dès
  /// que deux membres portent le même nom.
  ///
  /// Vide quand le serveur ne connaît pas encore les mentions : le message
  /// s'affiche alors comme une phrase ordinaire, sans rien perdre.
  final List<MentionMessage> mentions;

  /// Le statut auquel ce message répond, recopié par le serveur à l'envoi.
  final StatutCite? statutCite;

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
    this.editedAt,
    this.expiresAt,
    this.replyTo,
    this.reactions = const [],
    this.starred = false,
    this.mentions = const [],
    this.statutCite,
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
        statutCite: j["statutCite"] != null
            ? StatutCite.fromJson(j["statutCite"] as Map<String, dynamic>)
            : null,
        deletedAt: j["deletedAt"] != null
            ? DateTime.tryParse(j["deletedAt"] as String)
            : null,
        editedAt: j["editedAt"] != null
            ? DateTime.tryParse(j["editedAt"] as String)
            : null,
        expiresAt: j["expiresAt"] != null
            ? DateTime.tryParse(j["expiresAt"] as String)
            : null,
        media: ((j["media"] as List?) ?? [])
            .map((m) => MessageMedia.fromJson(m as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j["createdAt"] as String),
        reactions: ((j["reactions"] as List?) ?? [])
            .map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
            .toList(),
        starred: (j["starred"] as bool?) ?? false,
        mentions: ((j["mentions"] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MentionMessage.fromJson)
            .toList(),
      );
}

/// UNE MENTION `@` : le compte visé, et le texte écrit dans le message.
///
/// ⚠️ [libelle] N'EST PAS LE PSEUDO COURANT, c'est ce qui a été inséré à
/// l'envoi, figé par le serveur. Deux raisons : c'est ce texte qu'il faut
/// retrouver dans le message pour le mettre en évidence — un pseudo changé
/// depuis ne s'y trouverait plus — et cela garde lisible la mention d'une
/// personne qui a quitté le groupe.
class MentionMessage {
  const MentionMessage({required this.userId, required this.libelle});

  final String userId;
  final String libelle;

  factory MentionMessage.fromJson(Map<String, dynamic> j) => MentionMessage(
        userId: (j["userId"] as String?) ?? "",
        libelle: (j["libelle"] as String?) ?? "",
      );

  Map<String, dynamic> toJson() => {"userId": userId, "libelle": libelle};
}
