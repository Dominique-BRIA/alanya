class CallRecord {
  final String id;
  final String? convId;
  final String type;
  final String status;
  final bool isOutgoing;
  final bool isGroup;
  final String peerName;
  final String? peerNumber;
  final String? peerAvatarUrl;
  final int participantCount;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int? durationSec;

  /// Identifiant de celui qui a lancé l'appel. Sert à trancher de quel côté
  /// sortir la bulle dans le fil, sans dépendre d'un booléen : le même appel
  /// est sortant pour l'un et entrant pour l'autre.
  final String? callerId;

  // ── Libellés calculés par le SERVEUR, déjà formulés pour ce destinataire ──
  //
  // Tous nullables, et c'est délibéré : un mobile à jour peut parler à un
  // serveur qui ne les envoie pas encore. Dans ce cas ils valent nul et le
  // client retombe sur son ancien calcul local. Sans cette précaution, tout
  // l'écran d'appels se viderait le temps du déploiement.
  final String? preciseStatus;
  final String? detail;
  final bool? isFailed;
  final String? colorHint;

  CallRecord({
    required this.id,
    required this.convId,
    required this.type,
    required this.status,
    required this.isOutgoing,
    required this.isGroup,
    required this.peerName,
    required this.peerNumber,
    required this.peerAvatarUrl,
    required this.participantCount,
    required this.startedAt,
    required this.answeredAt,
    required this.endedAt,
    required this.durationSec,
    this.callerId,
    this.preciseStatus,
    this.detail,
    this.isFailed,
    this.colorHint,
  });

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
        id: j["id"] as String,
        convId: j["convId"] as String?,
        type: j["type"] as String,
        status: j["status"] as String,
        isOutgoing: (j["isOutgoing"] as bool?) ?? false,
        isGroup: (j["isGroup"] as bool?) ?? false,
        peerName: j["peerName"] as String? ?? "Inconnu",
        peerNumber: j["peerNumber"] as String?,
        peerAvatarUrl: j["peerAvatarUrl"] as String?,
        participantCount: (j["participantCount"] as num?)?.toInt() ?? 2,
        startedAt: DateTime.parse(j["startedAt"] as String),
        answeredAt: j["answeredAt"] == null ? null : DateTime.parse(j["answeredAt"] as String),
        endedAt: j["endedAt"] == null ? null : DateTime.parse(j["endedAt"] as String),
        durationSec: (j["durationSec"] as num?)?.toInt(),
        callerId: j["callerId"] as String?,
        preciseStatus: j["preciseStatus"] as String?,
        detail: j["detail"] as String?,
        isFailed: j["isFailed"] as bool?,
        colorHint: j["colorHint"] as String?,
      );

  /// Sérialisation pour le cache local.
  ///
  /// Les libellés du serveur sont conservés : sans eux, un appel relu depuis le
  /// cache repasserait par le calcul de repli et pourrait changer de texte
  /// entre deux affichages du même écran.
  Map<String, dynamic> toJson() => {
        "id": id,
        "convId": convId,
        "type": type,
        "status": status,
        "isOutgoing": isOutgoing,
        "isGroup": isGroup,
        "peerName": peerName,
        "peerNumber": peerNumber,
        "peerAvatarUrl": peerAvatarUrl,
        "participantCount": participantCount,
        "startedAt": startedAt.toIso8601String(),
        "answeredAt": answeredAt?.toIso8601String(),
        "endedAt": endedAt?.toIso8601String(),
        "durationSec": durationSec,
        "callerId": callerId,
        "preciseStatus": preciseStatus,
        "detail": detail,
        "isFailed": isFailed,
        "colorHint": colorHint,
      };

  /// De quel côté afficher la bulle dans le fil.
  ///
  /// Repart de `callerId` quand le serveur le fournit : c'est le fait brut. Le
  /// `isOutgoing` reste un repli — il est correct, le serveur le calcule par
  /// destinataire, mais il ne se vérifie pas localement.
  bool emisPar(String? myId) {
    if (callerId != null && myId != null) return callerId == myId;
    return isOutgoing;
  }
}

class CallParticipantInfo {
  final String userId;
  final String displayName;

  /// Photo du participant. Seule source disponible quand on décroche
  /// APPLICATION FERMÉE : l'événement WebSocket d'appel entrant, qui la
  /// portait, n'a alors jamais été reçu.
  final String? avatarUrl;

  CallParticipantInfo({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  factory CallParticipantInfo.fromJson(Map<String, dynamic> j) => CallParticipantInfo(
        userId: j["userId"] as String,
        displayName: j["displayName"] as String? ?? "Membre",
        avatarUrl: j["avatarUrl"] as String?,
      );
}

/// Appel entrant reçu via WebSocket.
class IncomingCallInfo {
  final String callId;
  final String? convId;
  final String callType;
  final String callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final bool isGroup;
  final String? groupName;
  final int memberCount;
  /// Nom et Alanya ID du centre qui a routé cet appel vers moi (agent) — nuls
  /// pour un appel ordinaire. `ivrFromId` sert à interroger la file d'attente
  /// du centre (`/api/queue/live`, `/api/queue/history`) depuis l'écran d'appel.
  final String? ivrFrom;
  final String? ivrFromId;

  IncomingCallInfo({
    required this.callId,
    required this.convId,
    required this.callType,
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl,
    required this.isGroup,
    required this.groupName,
    required this.memberCount,
    this.ivrFrom,
    this.ivrFromId,
  });

  String get displayTitle =>
      isGroup ? (groupName ?? "Appel de groupe") : callerName;
}
