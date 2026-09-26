/// LE JOURNAL DU CHIFFREMENT — CE QUI PERMET DE SAVOIR OÙ ÇA CASSE.
///
/// 🔴 POURQUOI CE FICHIER EXISTE. Le 26/09/2026, le chiffrement ne marchait ni
/// à l'envoi ni à la réception, et **rien ne le disait**. La chaîne compte six
/// étapes réseau — publier ses clés, ouvrir les sessions, poser la ligne du
/// fil, déposer les enveloppes, les relever, les acquitter — et chacune était
/// enveloppée d'un `catch (_) {}` silencieux, pour de bonnes raisons prises une
/// par une (« un fil chiffré ne doit pas afficher d'erreur réseau là où un fil
/// ordinaire n'en montre pas »). Additionnées, ces raisons donnaient une
/// fonctionnalité qui ne marche pas et qui n'explique pas pourquoi.
///
/// ⚠️ CE FICHIER EST EN DART PUR, ET DOIT LE RESTER. `e2ee_service.dart` et
/// `e2ee_fil.dart` n'importent AUCUN paquet Flutter — c'est ce qui permet au
/// banc d'interopérabilité de les exécuter sans interface ni serveur. Y ajouter
/// `debugPrint` (qui vient de Flutter) leur ferait perdre cette propriété. Le
/// branchement vers le journal système se fait donc de l'extérieur, par
/// [tracer], posé une fois dans `main.dart`.
library;

/// Journal court et horodaté des étapes du chiffrement.
///
/// ⚠️ IL EST BORNÉ, ET C'EST UNE DÉCISION : c'est un instrument de diagnostic,
/// pas un historique. Quarante lignes suffisent à raconter un démarrage et un
/// message, et l'écran qui les affiche n'a pas à gérer une liste qui grandit.
class E2eeJournal {
  E2eeJournal._();

  static const int _max = 40;

  /// Où les lignes partent EN PLUS — `main.dart` y branche `traceAppel`, ce qui
  /// les envoie dans `adb logcat` et dans l'overlay de débogage.
  ///
  /// ⚠️ NUL PAR DÉFAUT : les services restent exécutables sans Flutter, et les
  /// tests purs Dart n'ont rien à brancher.
  static void Function(String ligne)? tracer;

  static final List<String> _lignes = <String>[];

  /// Les dernières lignes, de la plus récente à la plus ancienne.
  ///
  /// ⚠️ UNE COPIE, PAS LA LISTE. Un écran qui l'affiche ne doit pas pouvoir
  /// modifier le journal — et l'itérer pendant qu'une ligne arrive lèverait une
  /// erreur de modification concurrente.
  static List<String> get lignes => List<String>.unmodifiable(_lignes);

  /// Ajoute une ligne au journal.
  static void note(String ligne) {
    final t = DateTime.now();
    final horodate = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    _lignes.insert(0, '$horodate $ligne');
    while (_lignes.length > _max) {
      _lignes.removeLast();
    }
    tracer?.call(ligne);
  }

  /// Vide le journal — à la déconnexion, comme le reste du coffre.
  static void vider() => _lignes.clear();
}
