/// UN SEUL RAFRAÎCHISSEMENT DE SESSION À LA FOIS, QUEL QUE SOIT L'APPELANT.
///
/// 🔴 POURQUOI CE FICHIER EXISTE. Le serveur fait TOURNER le jeton de
/// rafraîchissement : chaque appel en révoque l'ancien. Deux rafraîchissements
/// lancés en même temps avec le même jeton, et le second se voit refuser — ce
/// que le client prenait pour « la session est morte ». L'utilisateur était
/// déconnecté sans que rien n'ait expiré.
///
/// Un verrou existait déjà, mais il vivait DANS `AuthedApi` et ne couvrait donc
/// que les requêtes passées par elle. `AuthController.bootstrap()` appelait le
/// dépôt directement : au démarrage de l'application — précisément le moment où
/// tout part en même temps, restauration de session, notifications en attente,
/// premiers écrans — les deux chemins se rafraîchissaient en parallèle.
///
/// ⚠️ LE VERROU EST STATIQUE, DONC PROPRE À SON ISOLAT. L'isolat d'arrière-plan
/// des notifications a le sien, et rien ne peut les faire communiquer : c'est
/// une limite de Dart, pas un oubli. C'est la raison pour laquelle le serveur
/// porte, de son côté, une fenêtre de grâce sur le rejeu d'un jeton déjà tourné
/// (`FENETRE_REJEU_MS`). Les deux parades sont nécessaires : celle-ci supprime
/// la course quand elle est évitable, celle du serveur rattrape le reste.
library;

class VerrouRafraichissement {
  VerrouRafraichissement._();

  static Future<String?>? _enCours;

  /// Exécute [travail] — ou, si un rafraîchissement est déjà en vol, attend
  /// CELUI-LÀ et rend son résultat.
  ///
  /// Rend le nouveau jeton d'accès, ou `null` quand le rafraîchissement n'a pas
  /// abouti sans pour autant condamner la session.
  ///
  /// ⚠️ LES EXCEPTIONS REMONTENT, elles ne sont pas avalées : c'est le code
  /// d'erreur du serveur — et lui seul — qui dit si la session est fermée. Un
  /// appelant qui préfère les ignorer le fait chez lui, en connaissance de
  /// cause.
  static Future<String?> partage(Future<String?> Function() travail) {
    final dejaEnVol = _enCours;
    if (dejaEnVol != null) return dejaEnVol;

    final futur = travail();
    _enCours = futur;
    // ⚠️ `whenComplete` et NON un `finally` après `await` : il faut libérer le
    // verrou que le travail réussisse ou échoue, sans transformer cette
    // fonction en `async` — sinon les appelants suivants recevraient un futur
    // déjà différent de celui qu'on vient de publier, et la course reviendrait.
    return futur.whenComplete(() {
      if (identical(_enCours, futur)) _enCours = null;
    });
  }

  /// Oublie le rafraîchissement en cours. Réservé aux tests.
  static void reinitialiserPourTest() => _enCours = null;
}
