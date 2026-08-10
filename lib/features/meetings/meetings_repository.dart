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
    // Protection : le backend peut renvoyer idMeeting ou id
    final id = res["idMeeting"] ?? res["id"];
    if (id == null) {
      throw Exception("Réponse invalide du serveur : idMeeting manquant");
    }
    return (id as num).toInt();
  }

  /// Rejoindre une réunion.
  Future<void> joinMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/join", {});
  }

  /// Quitter une réunion.
  Future<void> leaveMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/leave", {});
  }

  Future<void> declineMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/decline", {});
  }

  /// Terminer une réunion (organisateur uniquement).
  Future<void> endMeeting(int idMeeting) async {
    await _api.post("/api/meetings/$idMeeting/end", {});
  }

  /// Supprime une réunion terminée.
  Future<void> deleteMeeting(int idMeeting) async {
    await _api.delete("/api/meetings/$idMeeting/delete");
  }

  /// Ajoute des participants à une réunion — organisateur uniquement, avant
  /// comme pendant la séance.
  ///
  /// Renvoie le nombre de personnes RÉELLEMENT ajoutées : le serveur écarte
  /// sans erreur celles qui étaient déjà membres, la valeur peut donc être
  /// inférieure au nombre de numéros envoyés, voire nulle.
  Future<int> addParticipants(
    int idMeeting,
    List<String> publicNumbers,
  ) async {
    final res = await _api.post(
      "/api/meetings/$idMeeting/participants",
      {"publicNumbers": publicNumbers},
    );
    return (res["ajoutes"] as num?)?.toInt() ?? 0;
  }

  /// Propose quelqu'un à l'organisateur — pour un participant qui n'organise
  /// pas la réunion.
  ///
  /// ⚠️ La personne proposée n'est prévenue de RIEN à ce stade. Elle ne le sera
  /// que si l'organisateur accepte, et par une invitation ordinaire.
  Future<void> requestInvite(int idMeeting, String publicNumber) async {
    await _api.post(
      "/api/meetings/$idMeeting/invite-requests",
      {"publicNumber": publicNumber},
    );
  }

  /// Demandes d'ajout d'une réunion — organisateur uniquement.
  Future<List<MeetingInviteRequest>> fetchInviteRequests(int idMeeting) async {
    final res = await _api.get("/api/meetings/$idMeeting/invite-requests");
    final list = (res["demandes"] as List?) ?? const [];
    return list
        .map((e) =>
            MeetingInviteRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// L'organisateur tranche une demande.
  Future<void> decideInviteRequest(
    int idMeeting,
    int requestId, {
    required bool accepter,
  }) async {
    await _api.patch(
      "/api/meetings/$idMeeting/invite-requests/$requestId",
      {"accepter": accepter},
    );
  }
}
