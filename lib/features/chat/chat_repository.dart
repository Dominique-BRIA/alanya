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

  /// Supprime une conversation complète.
  Future<void> deleteConversation(String convId) async {
    await _api.delete("/api/conversations/$convId/delete");
  }

  /// F8 : Épingler/désépingler une conversation.
  Future<void> pinConversation(String convId, bool pinned) async {
    await _api.patch("/api/conversations/$convId/pin", {"pinned": pinned});
  }

  /// F9 : Archiver/désarchiver une conversation.
  Future<void> archiveConversation(String convId, bool archived) async {
    await _api.patch("/api/conversations/$convId/archive", {"archived": archived});
  }

  /// F9 : Liste les conversations archivées.
  Future<List<Conversation>> listArchived() async {
    final data = await _api.get("/api/conversations?archived=true");
    return ((data["conversations"] as List?) ?? [])
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .where((c) => c.isArchived)
        .toList();
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
  
    /// Modifier le nom/avatar d'un groupe.
  Future<void> updateGroup(String convId, {String? name, String? avatarUrl}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    await _api.patch("/api/conversations/$convId", body);
  }

  /// Ajouter des membres à un groupe.
  Future<void> addMembersToGroup(String convId, List<String> publicNumbers) async {
    await _api.post("/api/conversations/$convId/members", {"publicNumbers": publicNumbers});
  }

  /// Retirer un membre d'un groupe.
  Future<void> removeMemberFromGroup(String convId, String userId) async {
    await _api.delete("/api/conversations/$convId/members?userId=$userId");
  }

  /// Change le rôle d'un membre : "ADMIN" (promouvoir) ou "MEMBER" (rétrograder).
  Future<void> changeMemberRole(String convId, String userId, String role) async {
    await _api.patch("/api/conversations/$convId/members", {"userId": userId, "role": role});
  }

  /// Modifier le contenu d'un message texte (repli REST quand le WS est coupé).
  Future<void> editMessage(String convId, String messageId, String content) async {
    await _api.patch("/api/conversations/$convId/messages/$messageId", {"content": content});
  }

  /// Recherche texte dans tout l'historique d'une conversation.
  /// Renvoie [{id, senderId, content, createdAt}], du plus récent au plus ancien.
  Future<List<Map<String, dynamic>>> searchMessages(String convId, String q) async {
    final data = await _api.get(
        "/api/conversations/$convId/messages/search?q=${Uri.encodeQueryComponent(q)}");
    return ((data["results"] as List?) ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  /// Quitter un groupe.
  Future<void> leaveGroup(String convId) async {
    await _api.post("/api/conversations/$convId/leave", {});
  }

  /// Récupérer la liste des membres d'un groupe.
  Future<List<Map<String, dynamic>>> getGroupMembers(String convId) async {
    final data = await _api.get("/api/conversations/$convId/members");
    return (data["members"] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }
  

  /// Cherche ou crée une conversation 1-to-1 avec un utilisateur.
  Future<Map<String, dynamic>> getOrCreateDirectConversation(String targetUserId) async {
    final data = await _api.post("/api/conversations/direct", {
      "targetUserId": targetUserId,
    });
    return Map<String, dynamic>.from(data as Map);
  }

    Future<Message> sendMultiMedia(String convId, List<String> mediaIds, String msgType, {String? replyToId}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "type": msgType, "mediaIds": mediaIds,
      if (replyToId != null) "replyToId": replyToId,
    });
    return Message.fromJson(data as Map<String, dynamic>);
  }
}
