import '../core/alanya_id_formatter.dart';

/// Utilisateur bloqué — correspond à la table « blocked » du PDF.
class BlockedUser {
  final int idBlock;
  final String idCallerBlock; // userId de l'utilisateur bloqué
  final String? pseudo;
  final String? publicNumber;
  final String? avatarUrl;
  final DateTime dateBlock;

  BlockedUser({
    required this.idBlock,
    required this.idCallerBlock,
    this.pseudo,
    this.publicNumber,
    this.avatarUrl,
    required this.dateBlock,
  });

  /// Repli FORMATE — voir la note detaillee sur `Contact.displayName`.
  String get displayName =>
      pseudo ??
      (publicNumber == null ? null : formatAlanyaId(publicNumber!)) ??
      "Inconnu";

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        idBlock: (j["idBlock"] as num).toInt(),
        idCallerBlock: j["idCallerBlock"] as String,
        pseudo: j["pseudo"] as String?,
        publicNumber: j["publicNumber"] as String?,
        avatarUrl: j["avatarUrl"] as String?,
        dateBlock: DateTime.parse(j["dateBlock"] as String),
      );
}
