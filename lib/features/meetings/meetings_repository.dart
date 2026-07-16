import '../../core/authed_api.dart';
import '../../models/meeting.dart';

/// Repository pour les réunions planifiées (table « meeting » / « participant » du PDF).
class MeetingsRepository {
  final AuthedApi _api;

  MeetingsRepository(this._api);

  /// Récupère toutes les réunions de l'utilisateur (organisées ou participées).
  Future<List<Meeting>> fetchMeetings() async {
    final res = await _api.get("/api/meetings");
    final list = (res["meetings"] as List)
        .map((j) => Meeting.fromJson(j as Map<String, dynamic>))
        .toList();
    return list;
  }

  /// Récupère le détail d'une réunion par son ID.
  Future<Meeting> fetchMeeting(int idMeeting) async {
    final res = await _api.get("/api/meetings/$idMeeting");
    return Meeting.fromJson(res as Map<String, dynamic>);
  }

  /// Crée une réunion.
  ///
  /// [objet] — sujet de la réunion.
  /// [typeMedia] — 1 = audio, 2 = vidéo.
  /// [duree] — durée prévue en secondes (défaut 3600 = 1h).
  /// [participantNumbers] — liste de numéros public Alanya des invités.
  /// [startTime] — date de début (ISO 8601), défaut = maintenant.
  /// [room] — identifiant de salle personnalisé (auto-généré si absent).
  /// Crée une réunion et retourne son idMeeting.
  Future<int> createMeeting({
    required String objet,
    required int typeMedia,
    int duree = 3600,
    List<String>? participantNumbers,
    String? startTime,
    String? room,
  }) async {
    final body = <String, dynamic>{
      "objet": objet,
      "type_media": typeMedia,
      "duree": duree,
    };
    if (participantNumbers != null && participantNumbers.isNotEmpty) {
      body["participantNumbers"] = participantNumbers;
    }
    if (startTime != null) body["start_time"] = startTime;
    if (room != null) body["room"] = room;

    final res = await _api.post("/api/meetings", body);
    return (res["idMeeting"] as num).toInt();
  }

  /// Rejoindre une réunion (accepte l'invitation, marque comme connecté).
  Future<void> joinMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/join", {});
  }

  /// Quitter une réunion.
  Future<void> leaveMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/leave", {});
  }

  /// Terminer une réunion (organisateur uniquement).
  Future<void> endMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/end", {});
  }
}
