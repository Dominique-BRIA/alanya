import '../../core/authed_api.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';

class ChatRepository {
  ChatRepository(this._api);
  final AuthedApi _api;

  Future<List<Conversation>> listConversations() async {
    final data = await _api.get("/api/conversations");
    return ((data["conversations"] as List?) ?? [])
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Crée (ou récupère) une conversation directe avec un utilisateur via son numéro.
  Future<String> createDirect(String publicNumber) async {
    final data = await _api.post("/api/conversations", {"publicNumber": publicNumber});
    return data["id"] as String;
  }

  /// Crée une conversation de groupe avec un nom et les numéros publics des membres.
  Future<String> createGroup(String name, List<String> memberNumbers) async {
    final data = await _api.post("/api/conversations", {
      "name": name,
      "memberNumbers": memberNumbers,
    });
    return data["id"] as String;
  }

  Future<List<Message>> getMessages(String convId, {String? cursor}) async {
    final path = "/api/conversations/$convId/messages${cursor != null ? "?cursor=$cursor" : ""}";
    final data = await _api.get(path);
    return ((data["messages"] as List?) ?? [])
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<Message> sendText(String convId, String content, {String? replyToId}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "content": content,
      "type": "TEXT",
      if (replyToId != null) "replyToId": replyToId,
    });
    return Message.fromJson(data);
  }

  /// Envoi REST d'un message média (repli si le WebSocket est indisponible).
  Future<Message> sendMedia(String convId, String mediaId, String type, {String? replyToId}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "type": type,
      "mediaId": mediaId,
      if (replyToId != null) "replyToId": replyToId,
    });
    return Message.fromJson(data);
  }

  Future<void> markRead(String convId) async {
    await _api.post("/api/conversations/$convId/read", {});
  }

  /// Supprime un message : scope "me" (masque pour moi) ou "everyone" (efface pour tous).
  Future<void> deleteMessage(String convId, String messageId, {String scope = "me"}) async {
    await _api.delete("/api/conversations/$convId/messages/$messageId?scope=$scope");
  }

  /// Transfère un message vers une ou plusieurs conversations.
  Future<void> forwardMessage(String convId, String messageId, List<String> targetConvIds) async {
    await _api.post("/api/conversations/$convId/messages/forward", {
      "messageId": messageId,
      "targetConvIds": targetConvIds,
    });
  }
}
