import '../core/alanya_id_formatter.dart';
import 'call_record.dart';

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

  /// Repli FORMATE — voir la note detaillee sur `Contact.displayName`.
  String get displayName => pseudo ?? formatAlanyaId(publicNumber);
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
        lastSeen: j["lastSeen"] != null
            ? DateTime.tryParse(j["lastSeen"] as String)
            : null,
      );
}

class Conversation {
  final String id;
  final bool isGroup;
  final String? title;
  final String? avatarUrl;
  final List<ConvMember> members;
  final LastMessage? lastMessage;

  /// Dernier appel de la conversation, envoyé par le serveur au même titre que
  /// [lastMessage].
  ///
  /// Nullable pour deux raisons distinctes : la conversation peut n'avoir aucun
  /// appel, et le serveur peut ne pas encore envoyer ce champ. Dans les deux
  /// cas la liste retombe sur le chargement séparé de l'historique.
  final CallRecord? lastCall;

  /// Le serveur a-t-il ENVOYÉ le champ `lastCall` ?
  ///
  /// Distinct de `lastCall != null`, et cette distinction est nécessaire : une
  /// conversation sans aucun appel renvoie légitimement `null`. Sans ce
  /// booléen, impossible de dire si le serveur sait répondre — et donc de
  /// décider s'il faut encore charger l'historique séparément.
  final bool lastCallFourni;
  final int unread;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isArchived;

  /// Notifications coupées pour MOI dans cette conversation.
  ///
  /// 🔴 PAR PARTICIPANT, pas par conversation : c'est un choix personnel, et
  /// mettre en sourdine ne doit rien changer pour les autres membres. La
  /// colonne vit sur `participant`, côté serveur.
  ///
  /// ⚠️ ÊTRE EN SOURDINE, C'EST NE PAS ÊTRE DÉRANGÉ — pas cesser de recevoir.
  /// Le serveur écarte le destinataire de la POUSSÉE ; la conversation continue
  /// de se mettre à jour en direct chez qui la regarde, et le compteur de non
  /// lus fait son travail.
  ///
  /// Facultatif dans la charge : un serveur antérieur ne l'envoie pas, et
  /// l'interrupteur part alors de « non ».
  final bool sourdine;

  Conversation({
    required this.id,
    required this.isGroup,
    required this.title,
    required this.avatarUrl,
    required this.members,
    required this.lastMessage,
    required this.unread,
    required this.updatedAt,
    this.lastCall,
    this.lastCallFourni = false,
    this.isPinned = false,
    this.isArchived = false,
    this.sourdine = false,
  });

  /// Copie avec la sourdine changée — le reste est intact.
  ///
  /// La liste des conversations est reconstruite à partir de ces objets : sans
  /// copie, basculer l'interrupteur n'aurait aucun effet visible avant le
  /// prochain rafraîchissement complet.
  Conversation copieAvecSourdine(bool valeur) => Conversation(
        id: id,
        isGroup: isGroup,
        title: title,
        avatarUrl: avatarUrl,
        members: members,
        lastMessage: lastMessage,
        unread: unread,
        updatedAt: updatedAt,
        lastCall: lastCall,
        lastCallFourni: lastCallFourni,
        isPinned: isPinned,
        isArchived: isArchived,
        sourdine: valeur,
      );

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
        lastCall: j["lastCall"] == null
            ? null
            : CallRecord.fromJson(j["lastCall"] as Map<String, dynamic>),
        // La présence de la CLÉ, pas de la valeur : `"lastCall": null` est une
        // réponse valide d'un serveur à jour pour une conversation sans appel.
        lastCallFourni: j.containsKey("lastCall"),
        unread: (j["unread"] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(j["updatedAt"] as String),
        isPinned: (j["isPinned"] as bool?) ?? false,
        isArchived: (j["isArchived"] as bool?) ?? false,
        sourdine: (j["sourdine"] as bool?) ?? false,
      );
}
