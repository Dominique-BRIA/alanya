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

  /// Ce compte est-il concerné par le relevé de position ?
  ///
  /// ⚠️ C'EST LE SERVEUR QUI DÉCIDE, jamais le téléphone : seuls les comptes
  /// rattachés à une entreprise sont suivis. Un particulier reçoit `false` et
  /// l'application se comporte pour lui comme si la fonctionnalité n'existait
  /// pas — ni écran de divulgation, ni demande de permission, ni relevé.
  ///
  /// Faux par défaut : un serveur qui ne renvoie pas le champ ne doit surtout
  /// pas déclencher un suivi que personne n'a demandé.
  final bool suiviPosition;

  /// Cadence de relevé, en minutes, dictée par le serveur. La changer ne
  /// demandera donc aucune mise à jour des téléphones déjà déployés.
  final int suiviPositionIntervalleMin;

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
    this.suiviPosition = false,
    this.suiviPositionIntervalleMin = 5,
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
        // Non modifiables localement : ces deux-là viennent du serveur, et une
        // mise à jour de profil n'a aucune raison de les changer. Les omettre
        // ici les aurait remis à leur valeur par défaut à chaque `copyWith`,
        // donc coupé le suivi au premier changement de pseudo.
        suiviPosition: suiviPosition,
        suiviPositionIntervalleMin: suiviPositionIntervalleMin,
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
        lastSeen: json["lastSeen"] != null
            ? DateTime.tryParse(json["lastSeen"] as String)
            : null,
        exclus: (json["exclus"] as num?)?.toInt() ?? 0,
        suiviPosition: json["suiviPosition"] as bool? ?? false,
        suiviPositionIntervalleMin:
            (json["suiviPositionIntervalleMin"] as num?)?.toInt() ?? 5,
      );
}
