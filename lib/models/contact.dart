/// Résultat d'une recherche d'utilisateur par numéro public.
class UserSearchResult {
  final String id;
  final String publicNumber;
  final String? pseudo;
  final String? avatarUrl;
  final String? statusMsg;
  final bool alreadyContact;

  UserSearchResult({
    required this.id,
    required this.publicNumber,
    required this.pseudo,
    required this.avatarUrl,
    required this.statusMsg,
    required this.alreadyContact,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
        id: j["id"] as String,
        publicNumber: j["publicNumber"] as String,
        pseudo: j["pseudo"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
        statusMsg: j["statusMsg"] as String?,
        alreadyContact: (j["alreadyContact"] as bool?) ?? false,
      );
}

/// Un contact du répertoire.
class Contact {
  final String id;
  final String? alias;
  final bool isBlocked;
  final String userId;
  final String publicNumber;
  final String? pseudo;
  final String? avatarUrl;

  Contact({
    required this.id,
    required this.alias,
    required this.isBlocked,
    required this.userId,
    required this.publicNumber,
    required this.pseudo,
    required this.avatarUrl,
  });

  String get displayName => alias ?? pseudo ?? publicNumber;

  factory Contact.fromJson(Map<String, dynamic> j) {
    final user = j["user"] as Map<String, dynamic>;
    return Contact(
      id: j["id"] as String,
      alias: j["alias"] as String?,
      isBlocked: (j["isBlocked"] as bool?) ?? false,
      userId: user["id"] as String,
      publicNumber: user["publicNumber"] as String,
      pseudo: user["pseudo"] as String?,
      avatarUrl: user["avatarUrl"] as String?,
    );
  }
}
