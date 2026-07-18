/// Utilisateur authentifié tel que renvoyé par l'API.
class AuthUser {
  final String id;
  final String email;
  final String publicNumber;
  final String? pseudo;
  final String? avatarUrl;
  final String? statusMsg;
  final String? nom;
  final int? idPays;
  final int typeCompte;
  final int isOnline;
  final DateTime? lastSeen;
  final int exclus;

  AuthUser({
    required this.id,
    required this.email,
    required this.publicNumber,
    this.pseudo,
    this.avatarUrl,
    this.statusMsg,
    this.nom,
    this.idPays,
    this.typeCompte = 0,
    this.isOnline = 0,
    this.lastSeen,
    this.exclus = 0,
  });

  AuthUser copyWith({
    String? pseudo,
    String? avatarUrl,
    String? statusMsg,
    String? nom,
    int? idPays,
    int? typeCompte,
    int? isOnline,
    DateTime? lastSeen,
    int? exclus,
  }) =>
      AuthUser(
        id: id,
        email: email,
        publicNumber: publicNumber,
        pseudo: pseudo ?? this.pseudo,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        statusMsg: statusMsg ?? this.statusMsg,
        nom: nom ?? this.nom,
        idPays: idPays ?? this.idPays,
        typeCompte: typeCompte ?? this.typeCompte,
        isOnline: isOnline ?? this.isOnline,
        lastSeen: lastSeen ?? this.lastSeen,
        exclus: exclus ?? this.exclus,
      );

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json["id"] as String,
        email: json["email"] as String,
        publicNumber: json["publicNumber"] as String,
        pseudo: json["pseudo"] as String?,
        avatarUrl: json["avatarUrl"] as String?,
        statusMsg: json["statusMsg"] as String?,
        nom: json["nom"] as String?,
        idPays: (json["idPays"] as num?)?.toInt(),
        typeCompte: (json["typeCompte"] as num?)?.toInt() ?? 0,
        isOnline: (json["isOnline"] as num?)?.toInt() ?? 0,
        lastSeen: json["lastSeen"] != null ? DateTime.tryParse(json["lastSeen"] as String) : null,
        exclus: (json["exclus"] as num?)?.toInt() ?? 0,
      );
}
