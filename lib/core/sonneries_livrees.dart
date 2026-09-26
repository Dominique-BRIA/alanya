/// LES SONNERIES LIVRÉES AVEC L'APPLICATION, par opposition à celles qu'un
/// compte importe dans son catalogue.
///
/// 🔴 LE CHAMP `ringtone` D'UNE LISTE ACCEPTE DEUX FORMES, et c'est le contrat
/// du serveur : soit une URL de média (`/api/media/<id>`), soit un simple NOM DE
/// FICHIER livré avec les clients. Les quatre listes créées d'office pour tout
/// le monde — Bureau, Amis, Confiance, Famille — portent la seconde forme.
///
/// C'est délibéré, et `backend-alanya/src/lib/listes-par-defaut.ts` le dit :
/// poser ces quatre sons en base aurait créé quatre lignes de catalogue et
/// quatre fichiers de stockage PAR COMPTE, pour un contenu strictement
/// identique chez tout le monde. Livrés avec le client, ils pèsent une fois.
///
/// 🔴 CE FICHIER EST NÉ D'UN DÉFAUT, et il faut savoir lequel pour ne pas le
/// refaire. Le mobile ne connaissait QUE la première forme : il collait l'URL de
/// l'API devant la valeur, quelle qu'elle soit. Pour « liste-bureau.mp3 » cela
/// donnait `https://…comliste-bureau.mp3` — sans même la barre oblique. Les
/// quatre sonneries livrées ne pouvaient donc PAS sonner sur Android, alors que
/// tout le reste de la chaîne était en place.
///
/// ⚠️ MIROIR DES ENTRÉES LIVRÉES DE `STAGE-WEB/src/services/ringtones.ts`. Les
/// noms de fichiers doivent rester identiques au caractère près : c'est cette
/// chaîne exacte qui est stockée en base et lue par les deux clients. Un
/// libellé peut diverger, un nom de fichier jamais.
library;

/// À QUOI SERT UN SON : sonner un appel, ou annoncer un message.
///
/// 🔴 LE CATALOGUE LIVRÉ ÉTAIT UNE SEULE LISTE À PLAT, et les deux champs de
/// l'écran des sonneries y puisaient tous les deux intégralement : on se voyait
/// proposer « Ping » ou « Goutte » comme sonnerie d'appel, et « Sonnerie 3 » —
/// trente secondes de sonnerie en boucle — à l'arrivée d'un message.
///
/// ⚠️ LE GENRE NE CHANGE RIEN À CE QUI EST STOCKÉ. La base ne connaît que le nom
/// du fichier, et les deux colonnes restent interchangeables : un choix posé
/// avant ce champ continue de se lire et de se jouer. Le genre ne filtre QUE ce
/// qu'on propose.
///
/// ⚠️ LES SONS IMPORTÉS N'EN ONT PAS, et c'est délibéré : l'utilisateur a
/// televersé son fichier pour en faire ce qu'il veut. Ils restent proposés aux
/// deux champs.
enum GenreSonnerie {
  /// Longue, en boucle : elle doit tenir le temps qu'on décroche.
  appel,

  /// Brève, jouée une fois : elle annonce, elle n'attend pas.
  message,
}

class SonnerieLivree {
  const SonnerieLivree(this.fichier, this.libelle, this.genre);

  /// Le nom stocké en base — « liste-bureau.mp3 ».
  final String fichier;

  /// Ce que l'utilisateur lit dans la liste déroulante.
  final String libelle;

  /// Le champ auquel ce son est proposé. Voir [GenreSonnerie].
  final GenreSonnerie genre;

  /// Le chemin que `AssetSource` attend : relatif à `assets/`, sans ce préfixe.
  String get asset => "sounds/$fichier";
}

/// ⚠️ N'Y METTRE QUE DES FICHIERS RÉELLEMENT PRÉSENTS DANS `assets/sounds/`.
///
/// Le web en propose deux de plus (`ringtone.mp3`, `message.mp3`) que le mobile
/// n'embarque pas. Les lister ici les rendrait choisissables et parfaitement
/// muets — [assetDeSonnerie] refuse donc tout ce qui n'est pas dans ce tableau,
/// et l'appel sonne alors avec la sonnerie par défaut plutôt qu'en silence.
const sonneriesLivrees = <SonnerieLivree>[
  // Les quatre sonneries des listes créées d'office.
  SonnerieLivree("liste-bureau.mp3", "Bureau", GenreSonnerie.appel),
  SonnerieLivree("liste-amis.mp3", "Amis", GenreSonnerie.appel),
  SonnerieLivree("liste-confiance.mp3", "Confiance", GenreSonnerie.appel),
  SonnerieLivree("liste-famille.mp3", "Famille", GenreSonnerie.appel),
  // Les trois sons historiques d'Alanya, déjà embarqués. Mêmes libellés que le
  // web, pour qu'un même choix se lise pareil sur les deux plateformes.
  SonnerieLivree("incoming_ring.mp3", "Sonnerie Alanya", GenreSonnerie.appel),
  SonnerieLivree("outgoing_ring.mp3", "Tonalité Alanya", GenreSonnerie.appel),
  SonnerieLivree(
    "notification.mp3",
    "Notification Alanya",
    GenreSonnerie.message,
  ),
  // Le catalogue livré, ajouté le 11/09/2026 : huit sonneries d'appel et dix
  // sons courts de notification. Avant, choisir « une autre sonnerie » voulait
  // dire importer un fichier depuis son téléphone — un catalogue vide ne se
  // parcourt pas.
  //
  // ⚠️ FORMAT OGG, ET C'EST VOULU : à qualité égale il pèse la moitié d'un MP3,
  // et Android le lit nativement. Voir la note de `STAGE-WEB` : Safari ne sait
  // pas le lire, ces entrées ne sont donc pas proposées au web.
  SonnerieLivree("sonnerie-1.ogg", "Sonnerie 1", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-2.ogg", "Sonnerie 2", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-3.ogg", "Sonnerie 3", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-4.ogg", "Sonnerie 4", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-5.ogg", "Sonnerie 5", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-6.ogg", "Sonnerie 6", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-7.ogg", "Sonnerie 7", GenreSonnerie.appel),
  SonnerieLivree("sonnerie-8.ogg", "Sonnerie 8", GenreSonnerie.appel),
  SonnerieLivree("notif-blip.ogg", "Bip", GenreSonnerie.message),
  SonnerieLivree("notif-bloom.ogg", "Éclosion", GenreSonnerie.message),
  SonnerieLivree("notif-chime.ogg", "Carillon", GenreSonnerie.message),
  SonnerieLivree("notif-drop.ogg", "Goutte", GenreSonnerie.message),
  SonnerieLivree("notif-duo.ogg", "Duo", GenreSonnerie.message),
  SonnerieLivree("notif-ping.ogg", "Ping", GenreSonnerie.message),
  SonnerieLivree("notif-pop.ogg", "Pop", GenreSonnerie.message),
  SonnerieLivree("notif-tap.ogg", "Tape", GenreSonnerie.message),
  SonnerieLivree("notif-tick.ogg", "Tic", GenreSonnerie.message),
  SonnerieLivree("notif-trio.ogg", "Trio", GenreSonnerie.message),
];

/// Le chemin d'asset correspondant à [valeur], ou `null` si ce n'en est pas une.
///
/// ⚠️ LE TEST PORTE SUR L'APPARTENANCE AU TABLEAU, pas sur la forme de la
/// chaîne. « Pas de barre oblique, donc c'est un fichier livré » aurait semblé
/// suffisant, mais aurait accepté n'importe quelle valeur inattendue — un nom
/// mal saisi, une forme future du serveur — et produit un appel muet. Ici,
/// l'inconnu retombe sur la sonnerie par défaut, ce qui s'entend.
String? assetDeSonnerie(String? valeur) {
  if (valeur == null || valeur.isEmpty) return null;
  for (final s in sonneriesLivrees) {
    if (s.fichier == valeur) return s.asset;
  }
  return null;
}

/// Le libellé d'une sonnerie livrée, ou `null` si [valeur] n'en est pas une.
String? libelleDeSonnerie(String? valeur) {
  if (valeur == null || valeur.isEmpty) return null;
  for (final s in sonneriesLivrees) {
    if (s.fichier == valeur) return s.libelle;
  }
  return null;
}

/// Les sonneries livrées proposées pour [genre].
///
/// ⚠️ À UTILISER PARTOUT OÙ L'ON PROPOSE UN CHOIX, jamais `sonneriesLivrees`
/// directement : c'est ce tableau complet, offert aux deux champs, qui mélangeait
/// les sons de messages aux sonneries d'appel.
///
/// ⚠️ `assetDeSonnerie` et `libelleDeSonnerie`, elles, continuent de balayer le
/// tableau ENTIER — et c'est voulu : elles LISENT une valeur déjà stockée. Un
/// choix posé avant ce champ, ou depuis le web, doit rester jouable même s'il ne
/// serait plus proposé aujourd'hui.
List<SonnerieLivree> sonneriesLivreesPour(GenreSonnerie genre) =>
    sonneriesLivrees.where((s) => s.genre == genre).toList();

/// LE CANAL DE NOTIFICATION ANDROID qui joue [fichier], pour un MESSAGE.
///
/// 🔴 POURQUOI UN CANAL PAR SON, ET NON UN SON PAR NOTIFICATION. Depuis
/// Android 8, le son d'une notification est porté par son CANAL, et un canal
/// **ne peut plus changer de son après sa création** — ni par l'application, ni
/// par une mise à jour. Poser `sound:` sur la notification elle-même n'a aucun
/// effet une fois le canal créé. La seule façon de faire sonner deux listes
/// différemment est donc de leur donner deux canaux, et c'est ce que fait
/// WhatsApp.
///
/// ⚠️ LE CANAL HISTORIQUE `messages` RESTE LE DÉFAUT, et il ne doit pas changer
/// de nom : il existe déjà sur tous les téléphones où l'application est
/// installée, avec « Notification Alanya » pour son. Lui en donner un autre
/// créerait un canal neuf et l'utilisateur retrouverait ses réglages remis à
/// zéro — volume, vibration, importance.
///
/// C'est aussi pour cela que `notification.mp3` retombe dessus : son canal
/// dédié aurait joué exactement le même son sous un second nom.
///
/// ⚠️ SEULS LES SONS LIVRÉS ONT UN CANAL. Une sonnerie IMPORTÉE vit derrière
/// `/api/media/<id>`, protégée par un jeton : Android ne saurait pas la lire
/// depuis l'interface système, il faudrait la télécharger et l'exposer par un
/// `FileProvider`. Elle retombe donc sur le canal par défaut hors de
/// l'application — dans la conversation ouverte, elle se joue bien.
const canalMessageParDefaut = "messages";

/// Le nom de la ressource Android correspondant à [fichier], ou `null`.
///
/// ⚠️ `android/app/src/main/res/raw/` ET NON `assets/` : une ressource Android
/// n'accepte ni tiret ni point dans son nom, d'où `notif-blip.ogg` copié en
/// `notif_blip.ogg`. Les deux exemplaires sont voulus — le paquet Flutter joue
/// l'asset dans l'application, Android joue la ressource hors de l'application.
String? ressourceAndroidDuSon(String? fichier) {
  if (fichier == null || !fichier.startsWith("notif-")) return null;
  // On ne fabrique un nom que pour une entrée RÉELLEMENT au catalogue : une
  // valeur inconnue produirait un canal sans ressource, donc une notification
  // muette — ou pas de notification du tout sur Android 8+.
  final connu = sonneriesLivrees.any(
    (s) => s.fichier == fichier && s.genre == GenreSonnerie.message,
  );
  if (!connu) return null;
  return fichier.replaceAll("-", "_").replaceAll(".ogg", "");
}

/// L'identifiant du canal qui doit annoncer un message sonné par [fichier].
///
/// Retombe sur [canalMessageParDefaut] pour tout ce qui n'a pas de ressource :
/// « Par défaut », un son importé, ou une valeur qu'on ne connaît pas.
String canalMessagePour(String? fichier) {
  final res = ressourceAndroidDuSon(fichier);
  return res == null ? canalMessageParDefaut : "msg_$res";
}
