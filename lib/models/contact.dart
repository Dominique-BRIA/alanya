import '../core/alanya_id_formatter.dart';

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
  final int isOnline;
  final DateTime? lastSeen;

  Contact({
    required this.id,
    required this.alias,
    required this.isBlocked,
    required this.userId,
    required this.publicNumber,
    required this.pseudo,
    required this.avatarUrl,
    this.isOnline = 0,
    this.lastSeen,
  });

  /// Ce qu'on montre pour désigner ce contact.
  ///
  /// 🔴 LE REPLI EST FORMATÉ (18/08/2026). Il rendait `publicNumber` BRUT, si
  /// bien que tout écran listant des personnes affichait un numéro collé dès
  /// qu'elles n'avaient pas de pseudo — signalé par le user sur le transfert
  /// d'appel et l'ajout d'une personne à un appel, mais le défaut touchait tous
  /// les écrans à la fois, parce que le repli se décide ICI et non chez eux.
  ///
  /// ⚠️ Formater ce getter est sûr, vérifié avant de le faire :
  ///  - les trois écrans qui CHERCHENT dessus testent aussi `publicNumber`
  ///    brut, donc taper « 123456 » trouve toujours ;
  ///  - le `displayName` qui part sur le WebSocket ne vient PAS d'ici mais
  ///    d'`AuthUser` (`home_screen.dart`), le protocole n'est donc pas touché.
  String get displayName => alias ?? pseudo ?? formatAlanyaId(publicNumber);
  bool get online => isOnline == 1;

  String get onlineStatus {
    if (online) return "en ligne";
    if (lastSeen == null) return "";
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inMinutes < 1) return "vu à l'instant";
    if (diff.inMinutes < 60) return "vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "vu il y a ${diff.inHours}h";
    return "vu il y a ${diff.inDays}j";
  }

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
      isOnline: (user["isOnline"] as num?)?.toInt() ?? 0,
      lastSeen: user["lastSeen"] != null
          ? DateTime.tryParse(user["lastSeen"] as String)
          : null,
    );
  }
}
