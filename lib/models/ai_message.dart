class AiMessage {
  final String id;
  final String role; // USER | MODEL
  final String content;
  final DateTime createdAt;

  AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == "USER";

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: j["id"] as String,
        role: j["role"] as String,
        content: j["content"] as String,
        createdAt: DateTime.parse(j["createdAt"] as String),
      );
}
