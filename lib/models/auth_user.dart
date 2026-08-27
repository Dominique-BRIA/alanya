import '../core/alanya_id_formatter.dart';

/// Utilisateur authentifié tel que renvoyé par l'API.
class AuthUser {
  final String id;

  /// 🔴 NULLABLE DEPUIS LE 25/08/2026 : l'adresse est devenue FACULTATIVE à
  /// l'inscription. Un compte ouvert sans adresse se reprend par son identifiant
  /// de récupération, et le serveur renvoie `"email": null` pour lui.
  ///
  /// ⚠️ Le cast était `json["email"] as String`, qui LÈVE sur `null` au lieu de
  /// rendre nul — c'est la même famille de panne que le `as num?` sur une chaîne
  /// du 17/08/2026. Le premier compte sans adresse aurait fait échouer la
  /// lecture du profil, donc le démarrage de l'application, sans que
  /// `flutter analyze` n'en dise rien.
  final String? email;
  final String publicNumber;
  final String? pseudo;
  final String? avatarUrl;
  final String? statusMsg;
  final String? nom;

  /// Le numéro de LIGNE déclaré, en forme canonique.
  ///
  /// ⚠️ À NE PAS CONFONDRE AVEC [publicNumber], l'Alanya ID : celui-là est
  /// l'identité du compte — ce que les contacts ont enregistré et ce qu'on
  /// compose — et il ne change jamais. Celui-ci n'est qu'une information de
  /// contact, modifiable sous mot de passe depuis les réglages.
  final String? mobile;
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
    this.mobile,
    this.idPays,
    this.typeCompte = 0,
    this.isOnline = 0,
    this.lastSeen,
    this.exclus = 0,
    this.suiviPosition = false,
    this.suiviPositionIntervalleMin = 5,
  });

  /// Le nom sous lequel on se présente aux autres : en appel, en réunion, dans
  /// les listes.
  ///
  /// 🔴 LE NOM D'ABORD, PUIS LE PSEUDO, PUIS LE NUMÉRO. C'est exactement la
  /// règle du serveur (`src/lib/display-name.mjs`), et c'est volontaire : deux
  /// ordres différents feraient qu'une même personne s'appellerait autrement
  /// selon que le nom vienne d'une route REST ou de l'appareil.
  ///
  /// ⚠️ LE NUMÉRO DE REPLI EST FORMATÉ, conformément à la règle que
  /// `test/nom_affiche_test.dart` fixe pour tous les modèles : quand on montre
  /// un numéro à la place d'un nom, il est formaté. Un « 12345678 » collé au
  /// milieu d'une liste de noms se lit mal, et c'est ce défaut-là qui avait
  /// été signalé au transfert d'appel.
  ///
  /// ⚠️ CE GETTER PART SUR LE RÉSEAU (`bindUser`, `home_screen.dart`) : c'est
  /// le nom que les autres voient s'afficher chez eux. Le changer change ce
  /// qu'ils lisent.
  String get nomAffiche {
    final n = nom?.trim();
    if (n != null && n.isNotEmpty) return n;
    final p = pseudo?.trim();
    if (p != null && p.isNotEmpty) return p;
    return formatAlanyaId(publicNumber);
  }

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
        mobile: mobile,
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
        email: json["email"] as String?,
        publicNumber: json["publicNumber"] as String,
        pseudo: json["pseudo"] as String?,
        avatarUrl: json["avatarUrl"] as String?,
        statusMsg: json["statusMsg"] as String?,
        nom: json["nom"] as String?,
        mobile: json["mobile"] as String?,
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
