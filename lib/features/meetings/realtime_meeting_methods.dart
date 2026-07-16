// Méthodes à ajouter dans RealtimeClient (lib/core/realtime_client.dart)
// Ajouter ces 3 méthodes après les méthodes callState/callSignal existantes :

  void meetingJoin(int meetingId) =>
      _send({"type": "meeting_join", "meetingId": meetingId});

  void meetingLeave(int meetingId) =>
      _send({"type": "meeting_leave", "meetingId": meetingId});

  void meetingSignal(int meetingId, String toUserId, Map<String, dynamic> signal) =>
      _send({
        "type": "meeting_signal",
        "meetingId": meetingId,
        "toUserId": toUserId,
        "signal": signal,
      });
