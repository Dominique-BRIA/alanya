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

class SonnerieLivree {
  const SonnerieLivree(this.fichier, this.libelle);

  /// Le nom stocké en base — « liste-bureau.mp3 ».
  final String fichier;

  /// Ce que l'utilisateur lit dans la liste déroulante.
  final String libelle;

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
  SonnerieLivree("liste-bureau.mp3", "Bureau"),
  SonnerieLivree("liste-amis.mp3", "Amis"),
  SonnerieLivree("liste-confiance.mp3", "Confiance"),
  SonnerieLivree("liste-famille.mp3", "Famille"),
  // Les trois sons historiques d'Alanya, déjà embarqués. Mêmes libellés que le
  // web, pour qu'un même choix se lise pareil sur les deux plateformes.
  SonnerieLivree("incoming_ring.mp3", "Sonnerie Alanya"),
  SonnerieLivree("outgoing_ring.mp3", "Tonalité Alanya"),
  SonnerieLivree("notification.mp3", "Notification Alanya"),
  // Le catalogue livré, ajouté le 11/09/2026 : huit sonneries d'appel et dix
  // sons courts de notification. Avant, choisir « une autre sonnerie » voulait
  // dire importer un fichier depuis son téléphone — un catalogue vide ne se
  // parcourt pas.
  //
  // ⚠️ FORMAT OGG, ET C'EST VOULU : à qualité égale il pèse la moitié d'un MP3,
  // et Android le lit nativement. Voir la note de `STAGE-WEB` : Safari ne sait
  // pas le lire, ces entrées ne sont donc pas proposées au web.
  SonnerieLivree("sonnerie-1.ogg", "Sonnerie 1"),
  SonnerieLivree("sonnerie-2.ogg", "Sonnerie 2"),
  SonnerieLivree("sonnerie-3.ogg", "Sonnerie 3"),
  SonnerieLivree("sonnerie-4.ogg", "Sonnerie 4"),
  SonnerieLivree("sonnerie-5.ogg", "Sonnerie 5"),
  SonnerieLivree("sonnerie-6.ogg", "Sonnerie 6"),
  SonnerieLivree("sonnerie-7.ogg", "Sonnerie 7"),
  SonnerieLivree("sonnerie-8.ogg", "Sonnerie 8"),
  SonnerieLivree("notif-blip.ogg", "Bip"),
  SonnerieLivree("notif-bloom.ogg", "Éclosion"),
  SonnerieLivree("notif-chime.ogg", "Carillon"),
  SonnerieLivree("notif-drop.ogg", "Goutte"),
  SonnerieLivree("notif-duo.ogg", "Duo"),
  SonnerieLivree("notif-ping.ogg", "Ping"),
  SonnerieLivree("notif-pop.ogg", "Pop"),
  SonnerieLivree("notif-tap.ogg", "Tape"),
  SonnerieLivree("notif-tick.ogg", "Tic"),
  SonnerieLivree("notif-trio.ogg", "Trio"),
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
