/// LA BULLE D'UN MÉDIA CHIFFRÉ EN COURS D'ENVOI NE DOIT PAS SE PERDRE.
///
/// Fonctions PURES, sorties de `chat_screen.dart` pour pouvoir être éprouvées
/// sans l'écran : `test/envois_chiffres_fil_test.dart`.
///
/// 🐛 « QUAND J'ENVOIE UN PDF, IL NE S'AFFICHE PAS CHEZ MOI ; IL FAUT ROUVRIR
/// LA CONVERSATION » (user, 04/10/2026). La photo, elle, s'affichait.
///
/// La différence : le PDF se choisit dans le sélecteur de fichiers d'ANDROID,
/// qui met Alanya en arrière-plan ; la photo, dans la galerie d'Alanya. Au
/// retour, la connexion temps réel peut être coupée. Tant qu'elle l'est, le
/// relais `_poll` remplace toutes les 3 s la liste affichée par la page du
/// serveur — qui ne connaît pas la bulle d'attente `tmp-…`. La bulle
/// disparaissait, et à la fin de l'envoi le remplacement `tmp-…` → message
/// ne trouvait plus rien à remplacer : le message n'était ajouté nulle part.
///
/// ⚠️ LES ENVOIS ORDINAIRES N'ONT PAS CE DÉFAUT : leurs bulles sont rebâties
/// depuis `EnvoiMediaStore` à chaque `_rebuildCombined`. Un envoi chiffré ne
/// passe pas par ce magasin (sa file hors ligne renverrait le fichier EN
/// CLAIR) ; il lui faut donc ces deux gardes.
library;

import '../../models/message.dart';

/// La page du serveur [duServeur], plus les bulles d'attente de [affiches]
/// dont l'envoi chiffré est encore en cours ([enCours] : leurs `tempId`).
List<Message> garderEnvoisEnCours(
  List<Message> duServeur,
  List<Message> affiches,
  Set<String> enCours,
) {
  if (enCours.isEmpty) return duServeur;
  final presents = {for (final m in duServeur) m.id};
  final attente = [
    for (final m in affiches)
      if (enCours.contains(m.id) && !presents.contains(m.id)) m,
  ];
  return attente.isEmpty ? duServeur : [...duServeur, ...attente];
}

/// Remplace la bulle d'attente [tempId] par le message [envoye].
///
/// 🔴 LE MESSAGE EST AJOUTÉ MÊME SI LA BULLE D'ATTENTE A DISPARU — c'était
/// tout le défaut : ne rien trouver à remplacer revenait à ne rien afficher.
///
/// 🔴 LA VERSION DU SERVEUR, S'IL Y EN A UNE, EST RETIRÉE. Elle a pu arriver
/// d'abord (relais, écho) et n'a pas le descripteur : c'est [envoye], qui le
/// porte, qui doit rester — sinon la bulle afficherait « indisponible ».
List<Message> remplacerEnvoiChiffre(
  List<Message> affiches,
  String tempId,
  Message envoye,
) {
  final sansDoublon = [
    for (final m in affiches)
      if (m.id != envoye.id) m,
  ];
  final i = sansDoublon.indexWhere((m) => m.id == tempId);
  if (i < 0) return [...sansDoublon, envoye];
  return [...sansDoublon]..[i] = envoye;
}
