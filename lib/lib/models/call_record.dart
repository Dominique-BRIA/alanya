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
      );
}

class CallParticipantInfo {
  final String userId;
  final String displayName;
  CallParticipantInfo({required this.userId, required this.displayName});

  factory CallParticipantInfo.fromJson(Map<String, dynamic> j) => CallParticipantInfo(
        userId: j["userId"] as String,
        displayName: j["displayName"] as String? ?? "Membre",
      );
}

/// Appel entrant reçu via WebSocket.
class IncomingCallInfo {
  final String callId;
  final String? convId;
  final String callType;
  final String callerId;
  final String callerName;
  final bool isGroup;
  final String? groupName;
  final int memberCount;

  IncomingCallInfo({
    required this.callId,
    required this.convId,
    required this.callType,
    required this.callerId,
    required this.callerName,
    required this.isGroup,
    required this.groupName,
    required this.memberCount,
  });

  String get displayTitle =>
      isGroup ? (groupName ?? "Appel de groupe") : callerName;
}
