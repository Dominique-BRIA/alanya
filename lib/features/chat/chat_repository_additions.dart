// Méthodes à ajouter dans ChatRepository (lib/features/chat/chat_repository.dart)

  /// Modifier le nom/avatar d'un groupe.
  Future<void> updateGroup(String convId, {String? name, String? avatarUrl}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    await _api.patch("/api/conversations/$convId", body);
  }

  /// Ajouter des membres à un groupe (par numéro public).
  Future<void> addMembersToGroup(String convId, List<String> publicNumbers) async {
    await _api.post("/api/conversations/$convId/members", {
      "publicNumbers": publicNumbers,
    });
  }

  /// Retirer un membre d'un groupe.
  Future<void> removeMemberFromGroup(String convId, String userId) async {
    await _api.delete("/api/conversations/$convId/members?userId=$userId");
  }

  /// Quitter un groupe.
  Future<void> leaveGroup(String convId) async {
    await _api.post("/api/conversations/$convId/leave", {});
  }

  /// Récupérer la liste des membres d'un groupe.
  Future<List<Map<String, dynamic>>> getGroupMembers(String convId) async {
    final data = await _api.get("/api/conversations/$convId/members");
    return (data["members"] as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  /// Cherche ou crée une conversation 1-to-1 avec un utilisateur.
  /// Retourne {id, title, avatarUrl, ...} de la conversation.
  Future<Map<String, dynamic>> getOrCreateDirectConversation(String targetUserId) async {
    final data = await _api.post("/api/conversations/direct", {
      "targetUserId": targetUserId,
    });
    return Map<String, dynamic>.from(data as Map);
  }
