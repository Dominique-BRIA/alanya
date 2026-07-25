import '../../core/authed_api.dart';
import '../../models/ai_message.dart';

/// Résumé d'une conversation IA (pour la liste des conversations).
class AiThreadSummary {
  final String id;
  final String title;
  final String? lastMessage;
  AiThreadSummary({required this.id, required this.title, this.lastMessage});
}

class AiRepository {
  AiRepository(this._api);
  final AuthedApi _api;

  /// Liste des conversations IA (récent → ancien).
  Future<List<AiThreadSummary>> threads() async {
    final data = await _api.get("/api/ai/threads");
    return ((data["threads"] as List?) ?? []).map((t) {
      final m = t as Map<String, dynamic>;
      return AiThreadSummary(
        id: m["id"] as String,
        title: (m["title"] as String?) ?? "Conversation",
        lastMessage: m["lastMessage"] as String?,
      );
    }).toList();
  }

  /// Messages d'une conversation IA.
  Future<List<AiMessage>> threadMessages(String threadId) async {
    final data = await _api.get("/api/ai/threads/$threadId/messages");
    return ((data["messages"] as List?) ?? [])
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Envoie un message. `threadId` null = nouvelle conversation.
  /// Renvoie (threadId, réponse) — le threadId permet de poursuivre.
  Future<(String, AiMessage)> send(String message, {String? threadId}) async {
    final data = await _api.post("/api/ai/chat", {
      "message": message,
      if (threadId != null) "threadId": threadId,
    });
    final tid = data["threadId"] as String;
    final reply = AiMessage.fromJson(data["reply"] as Map<String, dynamic>);
    return (tid, reply);
  }

  /// Supprime une conversation IA.
  Future<void> deleteThread(String threadId) async {
    await _api.delete("/api/ai/threads/$threadId");
  }

  // --- Compat (ancien thread unique) ---
  Future<List<AiMessage>> history() async {
    final data = await _api.get("/api/ai/messages");
    return ((data["messages"] as List?) ?? [])
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() async {
    await _api.delete("/api/ai/messages");
  }
}
