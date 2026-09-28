/// RETENTER UNE OPÉRATION RÉSEAU QUI ÉCHOUE, QUELQUES FOIS, PUIS ABANDONNER.
///
/// Fonction PURE (sans Flutter), éprouvée par `test/avec_reprises_test.dart`.
///
/// 🐛 POURQUOI ELLE EXISTE. À l'ouverture d'une conversation juste après une
/// coupure réseau, la relève des messages chiffrés partait avant que le réseau
/// soit vraiment revenu, échouait, et l'échec était avalé : tous les messages
/// reçus pendant la coupure restaient « indisponibles sur cet appareil »
/// jusqu'à ce qu'on rouvre le fil (signalé par le user le 29/09/2026).
library;

/// Appelle [operation] ; si elle lève, réessaie après chacun des [delais],
/// tant que [continuer] répond vrai (l'écran est-il toujours là ?).
///
/// Rend le résultat du premier essai réussi, ou `null` si tous ont échoué ou
/// si [continuer] a dit non. Ne lève jamais.
Future<T?> avecReprises<T>(
  Future<T> Function() operation, {
  List<Duration> delais = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ],
  bool Function()? continuer,
  Future<void> Function(Duration)? attendre,
}) async {
  final pause = attendre ?? (d) => Future<void>.delayed(d);
  for (var essai = 0; essai <= delais.length; essai++) {
    if (essai > 0) {
      await pause(delais[essai - 1]);
    }
    if (continuer != null && !continuer()) return null;
    try {
      return await operation();
    } catch (_) {
      // On réessaiera, s'il reste un délai.
    }
  }
  return null;
}
