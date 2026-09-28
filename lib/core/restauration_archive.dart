/// CE QU'UNE LIGNE DE L'ARCHIVE A LE DROIT DE FAIRE AU CACHE LOCAL.
///
/// Fonction PURE, sortie de `MessageCache` pour pouvoir être éprouvée sans
/// base : `test/restauration_archive_test.dart`.
///
/// 🐛 LA RESTAURATION REMPLAÇAIT LA LIGNE ENTIÈRE. Elle écrivait par `upsert`,
/// donc `INSERT OR REPLACE` : `deleted_at`, `expires_at`, le statut, la réponse
/// citée et les mentions repartaient à zéro. Or elle tourne à chaque lancement
/// où l'archive a grossi — c'est-à-dire après chaque envoi. Un message
/// « supprimé pour tous » ou éphémère ressortait donc en clair, pour toujours.
///
/// 🐛 ET UNE LIGNE EFFACÉE REVENAIT. « Supprimer pour moi » et l'expiration
/// d'un éphémère RETIRENT la ligne ; l'archive, elle, garde le texte. Sans
/// mémoire de l'effacement, la restauration suivante la recréait.
library;

/// Le geste que la restauration fait sur une ligne.
enum GesteRestauration {
  /// La ligne n'existe pas : on la crée, avec son texte.
  inserer,

  /// La ligne existe sans texte (arrivée par le serveur, qui ne l'a pas) : on
  /// lui donne son texte, et RIEN d'autre.
  completerTexte,

  /// On n'y touche pas.
  rien,
}

/// Décide ce que la restauration fait d'un message de l'archive.
///
/// [efface] : le message a été effacé de cet appareil — supprimé pour moi, ou
/// éphémère expiré. [ligne] : la ligne actuelle du cache, `null` si absente.
GesteRestauration gesteRestauration({
  required bool efface,
  required ({String? texte, bool supprime})? ligne,
}) {
  // ⚠️ AVANT TOUT : une ligne effacée ne revient pas, même si elle est absente.
  if (efface) return GesteRestauration.rien;
  if (ligne == null) return GesteRestauration.inserer;
  // Supprimé pour tous : la ligne garde sa place, sans texte, pour toujours.
  if (ligne.supprime) return GesteRestauration.rien;
  // Un texte déjà là est au moins aussi juste que celui de l'archive.
  if ((ligne.texte ?? '').isNotEmpty) return GesteRestauration.rien;
  return GesteRestauration.completerTexte;
}
