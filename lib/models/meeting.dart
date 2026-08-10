/// Participant d'une réunion — correspond à la table « participant » du PDF.
class MeetingParticipant {
  final int id; // ID (PK)
  final int idMeeting;
  final String userId; // IDparticipant
  final String? pseudo;
  final String? publicNumber;
  final String? avatarUrl;
  final int status; // 0 = invité, 1 = accepté, 2 = décliné
  final int connecte; // 0 = déconnecté, 1 = connecté
  final DateTime? startTime; // moment réel de connexion
  final int? duree; // durée de participation en secondes

  MeetingParticipant({
    required this.id,
    required this.idMeeting,
    required this.userId,
    this.pseudo,
    this.publicNumber,
    this.avatarUrl,
    required this.status,
    required this.connecte,
    this.startTime,
    this.duree,
  });

  String get displayName => pseudo ?? publicNumber ?? "Inconnu";
  bool get isConnected => connecte == 1;

  factory MeetingParticipant.fromJson(Map<String, dynamic> j) =>
      MeetingParticipant(
        id: (j["ID"] as num).toInt(),
        idMeeting: (j["idMeeting"] as num?)?.toInt() ?? 0,
        userId: j["IDparticipant"] as String,
        pseudo: j["pseudo"] as String?,
        publicNumber: j["publicNumber"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
        status: (j["status"] as num).toInt(),
        connecte: (j["connecte"] as num?)?.toInt() ?? 0,
        startTime: j["start_time"] != null
            ? DateTime.tryParse(j["start_time"] as String)
            : null,
        duree: (j["duree"] as num?)?.toInt(),
      );
}

/// Réunion planifiée — correspond à la table « meeting » du PDF.
class Meeting {
  final int idMeeting;
  final String objet;
  final int typeMedia; // 1 = audio, 2 = vidéo
  final String room;
  final int isEnd; // 0 = actif, 1 = terminé
  final DateTime startTime;
  final int duree; // durée prévue en secondes
  final MeetingOrganizer organiser;
  final List<MeetingParticipant> participants;

  Meeting({
    required this.idMeeting,
    required this.objet,
    required this.typeMedia,
    required this.room,
    required this.isEnd,
    required this.startTime,
    required this.duree,
    required this.organiser,
    required this.participants,
  });

  bool get isFinished => isEnd == 1;
  bool get isVideo => typeMedia == 2;
  bool get isAudio => typeMedia == 1;

  /// Nombre de participants actuellement connectés.
  int get connectedCount => participants.where((p) => p.isConnected).length;

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        idMeeting: (j["idMeeting"] as num).toInt(),
        objet: j["objet"] as String,
        typeMedia: (j["type_media"] as num).toInt(),
        room: j["room"] as String,
        isEnd: (j["isEnd"] as num?)?.toInt() ?? 0,
        startTime: DateTime.parse(j["start_time"] as String),
        duree: (j["duree"] as num).toInt(),
        organiser:
            MeetingOrganizer.fromJson(j["organiser"] as Map<String, dynamic>),
        participants: ((j["participants"] as List?) ?? [])
            .map((p) => MeetingParticipant.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// Infos synthétiques de l'organisateur d'une réunion.
class MeetingOrganizer {
  final String id;
  final String? pseudo;
  final String? publicNumber;
  final String? avatarUrl;

  MeetingOrganizer({
    required this.id,
    this.pseudo,
    this.publicNumber,
    this.avatarUrl,
  });

  String get displayName => pseudo ?? publicNumber ?? "Inconnu";

  factory MeetingOrganizer.fromJson(Map<String, dynamic> j) => MeetingOrganizer(
        id: j["id"] as String,
        pseudo: j["pseudo"] as String?,
        publicNumber: j["publicNumber"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
      );
}

/// Demande d'un participant pour faire entrer quelqu'un dans une réunion.
///
/// N'est lisible que par l'organisateur : lui seul tranche, et un participant
/// n'a pas à savoir qui les autres ont proposé ni ce qui a été refusé.
class MeetingInviteRequest {
  static const enAttente = 0;
  static const acceptee = 1;
  static const refusee = 2;

  final int id;
  final int statut;
  final MeetingOrganizer demandeur;
  final MeetingOrganizer invite;
  final DateTime? createdAt;

  MeetingInviteRequest({
    required this.id,
    required this.statut,
    required this.demandeur,
    required this.invite,
    this.createdAt,
  });

  bool get estEnAttente => statut == enAttente;

  /// [MeetingOrganizer] est réutilisé pour les deux personnes : c'est la même
  /// forme (identifiant, pseudo, numéro, avatar) et la dupliquer sous un autre
  /// nom n'apporterait rien.
  factory MeetingInviteRequest.fromJson(Map<String, dynamic> j) =>
      MeetingInviteRequest(
        id: (j["id"] as num).toInt(),
        statut: (j["statut"] as num?)?.toInt() ?? 0,
        demandeur: MeetingOrganizer.fromJson(
            Map<String, dynamic>.from(j["demandeur"] as Map)),
        invite: MeetingOrganizer.fromJson(
            Map<String, dynamic>.from(j["invite"] as Map)),
        createdAt: j["createdAt"] != null
            ? DateTime.tryParse(j["createdAt"] as String)
            : null,
      );
}
