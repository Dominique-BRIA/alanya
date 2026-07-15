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
  });

  AuthUser copyWith({
    String? pseudo,
    String? avatarUrl,
    String? statusMsg,
    String? nom,
    int? idPays,
    int? typeCompte,
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
      );
}
