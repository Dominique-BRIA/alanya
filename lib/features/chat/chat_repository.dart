import 'dart:async';

import '../../core/authed_api.dart';
import '../../core/cache_ecrans.dart';
import '../../core/device_registry.dart';
import '../../core/message_cache.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../home/dernier_message_local.dart';

/// Donne aux fils CHIFFRÉS leur dernier texte, lu dans le cache local.
///
/// ⚠️ À APPLIQUER À TOUTE LISTE DE CONVERSATIONS AFFICHÉE — celle du serveur
/// comme celle du cache : le serveur rend `lastMessage: null` pour un fil
/// chiffré (il n’a pas le texte). Voir `dernier_message_local.dart`.
///
/// ⚠️ NE LÈVE JAMAIS : sans cache lisible, la liste s’affiche comme avant.
/// Trois secondes au plus, comme les autres lectures de `sqflite`.
Future<List<Conversation>> avecDerniersTextesLocaux(List<Conversation> convs) async {
  final chiffres = [for (final c in convs) if (c.e2eeActif) c.id];
  if (chiffres.isEmpty) return convs;
  try {
    final locaux = await MessageCache.derniersTextes(chiffres)
        .timeout(const Duration(seconds: 3));
    return appliquerDerniersTextes(convs, locaux);
  } catch (_) {
    return convs;
  }
}

class ChatRepository {
  ChatRepository(this._api);
  final AuthedApi _api;

  Future<List<Conversation>> listConversations() async {
    final data = await _api.get("/api/conversations");
    final convs = ((data["conversations"] as List?) ?? [])
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
    return avecDerniersTextesLocaux(convs);
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

  /// [limit] : taille de la page (50 par défaut côté serveur, 100 au plus).
  Future<List<Message>> getMessages(String convId, {String? cursor, int? limit}) async {
    final params = [
      if (cursor != null) "cursor=$cursor",
      if (limit != null) "limit=$limit",
    ];
    final path = "/api/conversations/$convId/messages${params.isEmpty ? "" : "?${params.join("&")}"}";
    final data = await _api.get(path);
    return ((data["messages"] as List?) ?? [])
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// [mentions] : les comptes visés par un `@`, chacun `{userId, libelle}`.
  ///
  /// ⚠️ CE CHEMIN EST LE REPLI du WebSocket, et il doit se comporter comme lui :
  /// une mention retenue en temps réel et perdue ici ferait dépendre la
  /// notification de l'état du réseau au moment de l'envoi.
  /// [statutCite] : l'identifiant du statut auquel ce message répond.
  ///
  /// ⚠️ SEUL L'IDENTIFIANT PART. L'aperçu (texte, image, couleur) est recopié
  /// par le serveur après contrôle de visibilité — sans quoi n'importe quel
  /// client pourrait fabriquer une citation d'un statut qu'il n'a jamais vu.
  /// [tempId] : l'identifiant que la file d'envois donne à ce message.
  ///
  /// 🔴 SANS LUI, UN REJEU CRÉE UN DOUBLON. `OutboxStore` ne retire son entrée
  /// qu'une fois la réponse reçue : si la coupure tombe APRÈS que le serveur a
  /// écrit le message mais AVANT que la réponse n'arrive, l'envoi est compté
  /// comme échoué et rejoué — le message part alors deux fois. Transmis, cet
  /// identifiant permet au serveur de reconnaître le rejeu et de renvoyer le
  /// message d'origine au lieu d'en écrire un second.
  ///
  /// ⚠️ Un serveur plus ancien l'ignore simplement : le champ est facultatif
  /// des deux côtés, et son absence ramène au comportement d'avant.
  Future<Message> sendText(String convId, String content,
      {String? replyToId,
      List<Map<String, String>>? mentions,
      String? statutCite,
      String? tempId}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "content": content,
      "type": "TEXT",
      if (replyToId != null) "replyToId": replyToId,
      if (statutCite != null) "statutCite": statutCite,
      if (mentions != null && mentions.isNotEmpty) "mentions": mentions,
      if (tempId != null) "tempId": tempId,
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

  /// Coupe ou rétablit les notifications de cette conversation, POUR MOI.
  ///
  /// ⚠️ ÊTRE EN SOURDINE, C'EST NE PAS ÊTRE DÉRANGÉ — pas cesser de recevoir.
  /// Le serveur écarte le destinataire de la poussée ; les messages arrivent,
  /// le compteur de non lus monte, le temps réel continue.
  ///
  /// Rend l'état RETENU PAR LE SERVEUR, et non celui qu'on espérait : c'est lui
  /// que l'écran doit afficher. Même règle que le web, dont la fiche de
  /// conversation basculait un état local sans rien envoyer nulle part.
  Future<bool> definirSourdine(String convId, bool sourdine) async {
    final data = await _api.post(
      "/api/conversations/$convId/sourdine",
      {"sourdine": sourdine},
    );
    return (data["sourdine"] as bool?) ?? sourdine;
  }

  /// F9 : Archiver/désarchiver une conversation.
  Future<void> archiveConversation(String convId, bool archived) async {
    await _api.patch("/api/conversations/$convId/archive", {"archived": archived});
  }

  /// F9 : Liste les conversations archivées.
  Future<List<Conversation>> listArchived() async {
    final data = await _api.get("/api/conversations?archived=true");
    final brut = (data["conversations"] as List?) ?? [];
    // Gardées pour la prochaine ouverture : la ligne « Archivées » et son
    // écran s'affichent sans attendre le réseau.
    await CacheEcrans.ecrire('conversations_archivees', [
      for (final c in brut)
        if (c is Map && c["isArchived"] == true) c,
    ]);
    return _archivees(brut);
  }

  /// Les dernières archivées reçues, sans réseau — `null` si aucune.
  Future<List<Conversation>?> listArchivedEnCache() async {
    final brut = await CacheEcrans.lire('conversations_archivees');
    if (brut is! List) return null;
    try {
      return _archivees(brut);
    } catch (_) {
      return null;
    }
  }

  List<Conversation> _archivees(List brut) => brut
      .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
      .where((c) => c.isArchived)
      .toList();

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

  /// Infos d'un message : accusés « lu » par membre (réservé à l'expéditeur).
  Future<Map<String, dynamic>> getMessageInfo(String convId, String messageId) async {
    final data =
        await _api.get("/api/conversations/$convId/messages/$messageId/info");
    return Map<String, dynamic>.from(data as Map);
  }

  /// Réglage courant des messages éphémères (durée en secondes, 0 = désactivé).
  Future<int> getDisappearing(String convId) async {
    final data = await _api.get("/api/conversations/$convId/disappearing");
    final s = (data["disappearingSeconds"] as num?)?.toInt() ?? 0;
    await CacheEcrans.ecrire('conv.$convId.ephemere', s);
    return s;
  }

  /// Le dernier réglage connu des messages éphémères — `null` si aucun.
  Future<int?> getDisappearingEnCache(String convId) async {
    final s = await CacheEcrans.lire('conv.$convId.ephemere');
    return s is num ? s.toInt() : null;
  }

  /// Règle le minuteur des messages éphémères — repli REST.
  Future<void> setDisappearing(String convId, int seconds) async {
    await _api.post(
        "/api/conversations/$convId/disappearing", {"seconds": seconds});
  }

  /// Message épinglé courant d'une conversation ({pinnedMessageId, message}).
  Future<Map<String, dynamic>> getPinned(String convId) async {
    final data = await _api.get("/api/conversations/$convId/pinned");
    final epingle = Map<String, dynamic>.from(data as Map);
    await CacheEcrans.ecrire('conv.$convId.epingle', epingle);
    return epingle;
  }

  /// Le dernier état connu du message épinglé — `null` si aucun.
  Future<Map<String, dynamic>?> getPinnedEnCache(String convId) async {
    final data = await CacheEcrans.lire('conv.$convId.epingle');
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// Épingle (messageId) ou détache (null) un message — repli REST.
  Future<void> pinMessage(String convId, String? messageId) async {
    await _api.post(
        "/api/conversations/$convId/pin-message", {"messageId": messageId});
  }

  /// Ajoute/retire un message des favoris (étoile), privé à l'utilisateur.
  Future<void> toggleStar(String convId, String messageId, bool starred) async {
    await _api.post(
        "/api/conversations/$convId/messages/$messageId/star", {"starred": starred});
  }

  /// Liste des messages favoris (toutes conversations), récent → ancien.
  Future<List<Map<String, dynamic>>> getStarred() async {
    final data = await _api.get("/api/starred");
    return ((data["starred"] as List?) ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
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
    final membres = (data["members"] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
    await CacheEcrans.ecrire('conv.$convId.membres', membres);
    return membres;
  }

  /// Les derniers membres connus du groupe — `null` si aucun.
  Future<List<Map<String, dynamic>>?> getGroupMembersEnCache(String convId) async {
    final data = await CacheEcrans.lire('conv.$convId.membres');
    if (data is! List) return null;
    return [for (final m in data) if (m is Map) Map<String, dynamic>.from(m)];
  }
  

  /// Cherche ou crée une conversation 1-to-1 avec un utilisateur.
  Future<Map<String, dynamic>> getOrCreateDirectConversation(String targetUserId) async {
    final data = await _api.post("/api/conversations/direct", {
      "targetUserId": targetUserId,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  /// Repli REST pour un message structuré (`CONTACT`, `LOCATION`) : la charge
  /// utile est le `content`, le média (photo d'un contact) est facultatif.
  Future<Message> sendStructured(String convId, String msgType, String content,
      {String? mediaId, String? replyToId}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "type": msgType,
      "content": content,
      if (mediaId != null) "mediaId": mediaId,
      if (replyToId != null) "replyToId": replyToId,
    });
    return Message.fromJson(data);
  }

  /// [mentions] : les `@` de la légende — même règle que pour un texte.
  Future<Message> sendMultiMedia(String convId, List<String> mediaIds, String msgType,
      {String? replyToId,
      String? content,
      List<Map<String, String>>? mentions,
      bool vueUnique = false}) async {
    final data = await _api.post("/api/conversations/$convId/messages", {
      "type": msgType, "mediaIds": mediaIds,
      if (vueUnique) "vueUnique": true,
      if (content != null && content.isNotEmpty) "content": content,
      if (replyToId != null) "replyToId": replyToId,
      if (mentions != null && mentions.isNotEmpty) "mentions": mentions,
    });
    return Message.fromJson(data as Map<String, dynamic>);
  }

  /// Ouvre un message à vue unique : le serveur écrit l'ouverture et rend le
  /// média, servi pendant [ResultatOuvertureVueUnique.fenetre].
  ///
  /// Lève [ApiException] : 403 EXPEDITEUR, 410 DEJA_OUVERTE ou EFFACEE.
  Future<ResultatOuvertureVueUnique> ouvrirVueUnique(String messageId) async {
    /*
     * 🔴 UNE VUE, UN APPAREIL (demande du user, 12/10/2026 : « si je l'ouvre
     * déjà avec mon compte sur un appareil, en allant sur l'autre appareil, on
     * ne doit pas pouvoir l'ouvrir »).
     *
     * Le serveur garantissait déjà UNE ouverture par COMPTE. Mais sa fenêtre de
     * reprise de cinq minutes — qui évite de perdre la photo quand le réseau
     * coupe en plein téléchargement — ne regardait pas QUI reprenait. En lui
     * disant quel appareil demande, la reprise est réservée à celui qui a
     * ouvert, et le second appareil est refusé.
     *
     * ⚠️ UN ÉCHEC DE LECTURE N'EMPÊCHE PAS D'OUVRIR : sans identifiant, le
     * serveur retombe sur son ancien comportement. Perdre la photo de quelqu'un
     * parce qu'une préférence locale est illisible serait pire.
     */
    String? appareil;
    try {
      appareil = await DeviceRegistry.instance.deviceId();
    } catch (_) {}
    final data = await _api.post(
      "/api/messages/$messageId/vue-unique",
      appareil == null ? {} : {"appareil": appareil},
    );
    return ResultatOuvertureVueUnique(
      media: ((data["media"] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MessageMedia.fromJson)
          .toList(),
      fenetre: Duration(seconds: (data["fenetreSecondes"] as num?)?.toInt() ?? 300),
    );
  }

  /// Le visionneur est refermé : le serveur clôt l'accès et efface le fichier
  /// si tous ont vu. Ne lève jamais — la purge du serveur rattrape un échec.
  Future<void> fermerVueUnique(String messageId) async {
    try {
      await _api.post("/api/messages/$messageId/vue-unique/fermer", {});
    } catch (_) {}
  }
}

class ResultatOuvertureVueUnique {
  const ResultatOuvertureVueUnique({required this.media, required this.fenetre});
  final List<MessageMedia> media;
  final Duration fenetre;
}
