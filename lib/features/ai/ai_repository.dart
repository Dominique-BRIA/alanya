import '../../core/authed_api.dart';
import '../../models/ai_message.dart';

class AiRepository {
  AiRepository(this._api);
  final AuthedApi _api;

  Future<List<AiMessage>> history() async {
    final data = await _api.get("/api/ai/messages");
    return ((data["messages"] as List?) ?? [])
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// Envoie un message à l'assistant et renvoie sa réponse.
  Future<AiMessage> send(String message) async {
    final data = await _api.post("/api/ai/chat", {"message": message});
    return AiMessage.fromJson(data["reply"] as Map<String, dynamic>);
  }

  /// Efface tout l'historique de la conversation IA.
  Future<void> clearHistory() async {
    await _api.delete("/api/ai/messages");
  }
}
