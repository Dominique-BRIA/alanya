import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../chat/chat_repository.dart';
import '../../contacts/contacts_repository.dart';
import '../../contacts/screens/add_contact_screen.dart';
import '../call_controller.dart';
import '../message_erreur_appel.dart';
import 'active_call_screen.dart';

/// Clavier d'appel : on compose un Alanya ID et on appelle directement.
///
/// Le chemin complet est en trois temps, parce que [CallController.startOutgoing]
/// EXIGE un identifiant de conversation :
///   1. recherche du compte (`/api/users/search`) — donne le nom à afficher et
///      prouve que l'ID existe avant de tenter quoi que ce soit ;
///   2. création (ou récupération) de la conversation directe ;
///   3. lancement de l'appel, puis ouverture de l'écran plein écran.
///
/// La recherche part toute seule dès que la saisie atteint une longueur valide
/// (6 ou 8 chiffres), avec un délai de grâce : sans ça il faudrait appuyer sur
/// la loupe pour savoir si on a composé le bon numéro, et l'erreur n'arriverait
/// qu'au moment d'appeler.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  /// Chiffres bruts, sans les espaces de présentation.
  String _digits = "";
  final _displayCtrl = TextEditingController();

  UserSearchResult? _found;
  String? _lookupError;
  bool _searching = false;
  bool _calling = false;
  Timer? _debounce;

  /// Même règle que partout ailleurs : 3 à 10 chiffres, décidée une seule fois
  /// dans `alanya_id_formatter.dart`.
  ///
  /// Elle valait « 6 ou 8 exactement », ce qui rendait un centre d'appels
  /// (4 chiffres) impossible à composer : le clavier n'activait jamais le bouton
  /// d'appel, sans le moindre message.
  bool get _isComplete => estAlanyaIdValide(_digits);

  @override
  void dispose() {
    _debounce?.cancel();
    _displayCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SAISIE
  // ---------------------------------------------------------------------------

  void _setDigits(String next) {
    setState(() {
      _digits = next;
      _displayCtrl.text = formatAlanyaId(next);
      // Toute frappe invalide le résultat affiché : il ne décrit plus la
      // saisie en cours.
      _found = null;
      _lookupError = null;
      _searching = false;
    });
    _scheduleLookup();
  }

  void _press(String digit) {
    if (_digits.length >= alanyaIdMaxLength) return;
    HapticFeedback.selectionClick();
    _setDigits(_digits + digit);
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    HapticFeedback.selectionClick();
    _setDigits(_digits.substring(0, _digits.length - 1));
  }

  void _clearAll() {
    if (_digits.isEmpty) return;
    HapticFeedback.mediumImpact();
    _setDigits("");
  }

  void _scheduleLookup() {
    _debounce?.cancel();
    if (!_isComplete) return;
    // Toute longueur de 3 à 10 est valide, et une saisie courte est presque
    // toujours une étape vers une plus longue : le délai de grâce compte donc
    // davantage qu'avant. On n'interroge le serveur que lorsque la frappe
    // s'arrête, jamais à chaque chiffre.
    _debounce = Timer(const Duration(milliseconds: 450), _lookup);
  }

  /// Cherche le compte correspondant à la saisie. Renvoie le résultat, ou nul
  /// si l'ID n'existe pas / la recherche a échoué.
  Future<UserSearchResult?> _lookup() async {
    if (!_isComplete) return null;
    final asked = _digits;
    setState(() {
      _searching = true;
      _lookupError = null;
    });
    try {
      final res =
          await context.read<ContactsRepository>().searchByNumber(asked);
      // La saisie a pu changer pendant l'aller-retour : le résultat porterait
      // alors sur un autre numéro que celui affiché.
      if (!mounted || asked != _digits) return null;
      setState(() {
        _found = res;
        _searching = false;
      });
      return res;
    } on ApiException catch (e) {
      if (!mounted || asked != _digits) return null;
      setState(() {
        _searching = false;
        _lookupError = e.statusCode == 404
            ? "Aucun compte avec cet Alanya ID"
            : "Recherche impossible (${e.statusCode})";
      });
      return null;
    } catch (_) {
      if (!mounted || asked != _digits) return null;
      setState(() {
        _searching = false;
        _lookupError = "Recherche impossible. Vérifie ta connexion.";
      });
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _call(String type) async {
    if (_calling) return;
    if (!_isComplete) {
      showAppSnackBar("Compose un Alanya ID à 6 ou 8 chiffres");
      return;
    }
    _debounce?.cancel();
    setState(() => _calling = true);
    try {
      // La recherche a pu ne pas encore avoir eu lieu (appel immédiat après la
      // dernière touche) : on la force avant d'engager l'appel.
      final user = _found ?? await _lookup();
      if (!mounted) return;
      if (user == null) {
        showAppSnackBar(_lookupError ?? "Aucun compte avec cet Alanya ID");
        return;
      }

      final title = user.pseudo ?? formatAlanyaId(user.publicNumber);
      final convId =
          await context.read<ChatRepository>().createDirect(user.publicNumber);
      if (!mounted) return;

      await context.read<CallController>().startOutgoing(convId, type, title);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(),
        ),
      );
    } catch (e) {
      // Le 404 est propre à cet écran : on y cherche un compte par son Alanya
      // ID, et son absence n'a pas le même sens depuis une conversation.
      showAppSnackBar(messageErreurAppel(e,
          messageSi404: "Aucun compte avec cet Alanya ID"));
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  Future<void> _addContact() async {
    if (!_isComplete) {
      showAppSnackBar("Compose un Alanya ID à 6 ou 8 chiffres");
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddContactScreen(initialNumber: _digits),
      ),
    );
    // Le contact a pu être ajouté entre-temps : la mention « déjà dans tes
    // contacts » serait périmée.
    if (mounted && _isComplete) _lookup();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Scaffold(
      backgroundColor: s.fond,
      appBar: backAppBar(
        context,
        "Clavier",
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "Chercher ce compte",
            onPressed: _isComplete && !_searching
                ? () {
                    _debounce?.cancel();
                    _lookup();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: "Appel vidéo",
            onPressed: _calling ? null : () => _call("VIDEO"),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _display(),
            const SizedBox(height: 6),
            _statusLine(),
            const SizedBox(height: 8),
            // Centré verticalement, et rendu défilant plutôt que tronqué :
            // sur un écran court, la grille déborderait sinon.
            Expanded(
              child: Center(
                child: SingleChildScrollView(child: _keypad()),
              ),
            ),
            _actions(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _display() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: _displayCtrl,
        readOnly: true,
        showCursor: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Alanya ID",
          hintStyle: TextStyle(
            color: faintOf(context, Colors.black26),
            fontSize: 28,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  /// Ligne d'état sous le champ : consigne, recherche en cours, compte trouvé
  /// ou erreur. Hauteur fixe pour que le clavier ne saute pas.
  Widget _statusLine() {
    Widget content;
    if (_searching) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: accentOf(context),
            ),
          ),
          const SizedBox(width: 8),
          Text("Recherche…",
              style: TextStyle(color: mutedOf(context, Colors.black54))),
        ],
      );
    } else if (_lookupError != null) {
      content = Text(
        _lookupError!,
        style: TextStyle(color: dangerOf(context)),
        textAlign: TextAlign.center,
      );
    } else if (_found != null) {
      final u = _found!;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            u.pseudo ?? "Utilisateur ${formatAlanyaId(u.publicNumber)}",
            style: TextStyle(
              color: positiveOf(context),
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if (u.alreadyContact)
            Text(
              "Déjà dans ton répertoire",
              style: TextStyle(
                  color: mutedOf(context, Colors.black54), fontSize: 12),
            ),
        ],
      );
    } else {
      content = Text(
        "$alanyaIdMinLength à $alanyaIdMaxLength chiffres",
        style: TextStyle(color: mutedOf(context, Colors.black45), fontSize: 13),
      );
    }
    return SizedBox(
      height: 44,
      child: Center(child: content),
    );
  }

  Widget _keypad() {
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      mainAxisSpacing: 14,
      crossAxisSpacing: 18,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _key("1"),
        _key("2", sub: "ABC"),
        _key("3", sub: "DEF"),
        _key("4", sub: "GHI"),
        _key("5", sub: "JKL"),
        _key("6", sub: "MNO"),
        _key("7", sub: "PQRS"),
        _key("8", sub: "TUV"),
        _key("9", sub: "WXYZ"),
        // Un Alanya ID est purement numérique : « * » et « # » seraient des
        // touches mortes. La case est laissée vide et « # » cède sa place au
        // retour arrière, à sa position habituelle sur un clavier d'appel.
        const SizedBox.shrink(),
        _key("0"),
        _backspaceKey(),
      ],
    );
  }

  Widget _key(String text, {String? sub}) {
    final cs = Theme.of(context).colorScheme;
    return _keyShell(
      onTap: () => _press(text),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sub != null)
            Text(
              sub,
              style: TextStyle(
                color: mutedOf(context, Colors.black45),
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _backspaceKey() {
    return _keyShell(
      onTap: _backspace,
      onLongPress: _clearAll,
      child: Icon(
        Icons.backspace_outlined,
        color: _digits.isEmpty
            ? faintOf(context, Colors.black26)
            : mutedOf(context, Colors.black54),
        size: 22,
      ),
    );
  }

  Widget _keyShell({
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Widget child,
  }) {
    final s = surfacesOf(context);
    return Material(
      color: s.surfaceHaute,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Center(child: child),
      ),
    );
  }

  Widget _actions() {
    final s = surfacesOf(context);
    final cs = Theme.of(context).colorScheme;
    // Vert dans les quatre thèmes : c'est la convention universelle du bouton
    // d'appel, elle ne doit pas suivre l'accent (qui vire au teal en Blanc et
    // en Noir). Seule la clarté est ajustée pour rester lisible sur fond sombre.
    final vertAppel = themed(context,
        light: AlanyaColors.forest, dark: AlanyaColors.forestLight);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            background: s.surfaceHaute,
            foreground:
                _isComplete ? cs.onSurface : faintOf(context, Colors.black26),
            icon: Icons.person_add_alt_1,
            tooltip: "Ajouter à mes contacts",
            onPressed: _isComplete ? _addContact : null,
            size: 56,
          ),
          _roundButton(
            background:
                _isComplete ? vertAppel : vertAppel.withValues(alpha: 0.35),
            foreground: Colors.white,
            icon: Icons.phone,
            tooltip: "Appeler",
            onPressed: _isComplete && !_calling ? () => _call("AUDIO") : null,
            size: 68,
            busy: _calling,
          ),
          // Pas de bouton « tout effacer » ici : l'appui long sur la touche
          // retour arrière le fait déjà, comme sur un clavier téléphonique.
        ],
      ),
    );
  }

  Widget _roundButton({
    required Color background,
    required Color foreground,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required double size,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  )
                : Icon(icon, color: foreground, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}
