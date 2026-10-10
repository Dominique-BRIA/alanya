import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/contact_cache.dart';
import '../../../core/texte_recherche.dart';
import '../../../models/auth_user.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../../chat/screens/new_group_screen.dart';
import '../contacts_repository.dart';
import 'contact_lists_screen.dart';
import 'new_chat_screen.dart';
import 'phone_sync_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact>? _contacts;

  /// Texte tapé dans la barre de recherche. Vide = aucun filtre.
  String _recherche = "";
  final _rechercheCtrl = TextEditingController();

  /// ⚠️ LA BARRE DE RECHERCHE A ENCORE DÉMÉNAGÉ (10/10/2026). Le 19/08 elle
  /// était passée dans l'en-tête, derrière une loupe ; elle est désormais
  /// TOUJOURS visible en haut de la liste, comme chez Chris — plus de geste
  /// pour l'ouvrir.

  /// Les contacts À AFFICHER : filtrés, puis classés alphabétiquement.
  ///
  /// ⚠️ Le tri se fait ICI, à l'affichage, et non sur `_contacts` : cette liste
  /// vient tantôt du cache local, tantôt du serveur, et rien ne garantit qu'ils
  /// la rendent dans le même ordre. Trier à la source obligerait à y penser aux
  /// deux endroits — et l'oubli ne se verrait qu'en mode hors ligne.
  ///
  /// La recherche porte sur le nom AFFICHÉ **et** sur le numéro : celui-ci
  /// n'apparaît pas dans le nom, et c'est pourtant par lui qu'on cherche
  /// quelqu'un qu'on n'a pas encore nommé.
  List<Contact> get _contactsAffiches {
    final tous = _contacts ?? const <Contact>[];
    /*
     * 🐛 « ZZZZZZ » RENDAIT LES 16 CONTACTS (user, 10/10/2026). Le numéro se
     * compare aux seuls CHIFFRES tapés ; une recherche sans chiffre en donnait
     * zéro — une chaîne vide, que tout numéro « contient ». Le numéro ne
     * compte donc que si l'on a tapé au moins un chiffre.
     */
    final chiffres = stripAlanyaId(_recherche);
    final filtres = _recherche.trim().isEmpty
        ? List<Contact>.from(tous)
        : tous
            .where((c) =>
                contientRecherche(c.displayName, _recherche) ||
                (chiffres.isNotEmpty && c.publicNumber.contains(chiffres)))
            .toList();
    filtres.sort((a, b) => comparePourTri(a.displayName, b.displayName));
    return filtres;
  }

  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Le contrôleur de la barre de recherche retient un écouteur : sans cette
    // libération, l'écran resterait référencé après sa fermeture.
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    // 1) Cache local d'abord (offline-first).
    final cached = await ContactCache.getAll();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _contacts = cached;
        _loading = false;
        _errorMsg = null;
      });
    }

    // 2) Rafraîchit depuis le serveur.
    try {
      final list = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
        _errorMsg = null;
      });
      await ContactCache.putAll(list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Ne montre l'erreur que si le cache était vide (aucun contenu à afficher).
        _errorMsg = (_contacts?.isEmpty ?? true)
            ? tr(context, 'error_with_code', {'code': '${e.statusCode}', 'message': e.message})
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = (_contacts?.isEmpty ?? true)
            ? tr(context, 'contacts_load_error')
            : null;
      });
    }
  }

  Future<void> _startChat(Contact c) async {
    final chat = context.read<ChatRepository>();
    try {
      final convId = await chat.createDirect(c.publicNumber);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: c.displayName,
            avatarUrl: c.avatarUrl,
            otherUserId: c.userId,
            otherPublicNumber: c.publicNumber,
            contactId: c.id,
            isBlocked: c.isBlocked,
          ),
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(tr(context, 'chat_open_failed'));
    }
  }

  Future<void> _toggleBlock(Contact c) async {
    try {
      await context.read<ContactsRepository>().setBlocked(c.id, !c.isBlocked);
      await _load();
    } catch (_) {
      // ⚠️ `tr()` LIT LE CONTEXTE, ce qu'un libellé en dur ne faisait pas :
      // après ces `await`, l'écran a pu être quitté, et lire le contexte d'un
      // widget démonté lève. La garde protège aussi le bandeau, qui n'en avait
      // aucune auparavant.
      if (!mounted) return;
      _snack(tr(context, 'action_failed'));
    }
  }

  Future<void> _remove(Contact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'contact_delete_q')),
        content: Text(tr(context, 'contact_delete_body', {'nom': c.displayName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'delete'))),
        ],
      ),
    );
    if (ok != true) return;
    // La boîte de dialogue est un `await` : l'écran a pu être quitté pendant
    // qu'elle était ouverte.
    if (!mounted) return;
    try {
      await context.read<ContactsRepository>().remove(c.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      _snack(tr(context, 'delete_failed'));
    }
  }

  void _snack(String m) => showAppSnackBar(m);

  /*
   * 🎨 DISPOSITION REFAITE (demande du user, 10/10/2026), sur le modèle de
   * l'écran de Chris : la recherche TOUJOURS visible en haut, les actions en
   * cartes côte à côte, puis « Moi », puis les contacts — chacun gardant son
   * Alanya ID en dessous du nom. Nos actions sont plus nombreuses que les
   * siennes (listes, import du répertoire) : elles tiennent en grille 2 × 2.
   */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(
        context,
        tr(context, 'contacts_title'),
        actions: [
          IconButton(
            tooltip: tr(context, 'refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      // Le fond uni du thème, comme Réunions (user, 10/10/2026) : le motif
      // rendait la liste et les cartes difficiles à lire.
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    // Chargement initial
    if (_contacts == null && _loading) {
      return Center(child: CircularProgressIndicator(color: accentOf(context)));
    }

    // Erreur avec bouton retry
    if (_errorMsg != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.cloud_off,
                      size: 48, color: faintOf(context, Colors.black26)),
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedOf(context, Colors.black54)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(tr(context, 'retry')),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accentOf(context)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final contacts = _contacts ?? [];
    final affiches = _contactsAffiches;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _champRecherche(),
            ),
            // Les actions s'effacent pendant une recherche : on cherche
            // quelqu'un, la liste doit remonter sous le doigt.
            if (_recherche.trim().isEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: _grilleActions(),
              ),
              _tuileMoi(),
            ],
            if (contacts.isNotEmpty)
              _titreSection(_recherche.trim().isEmpty
                  ? '${tr(context, 'contacts_title')} · ${contacts.length}'
                  : '${affiches.length}'),
            ...affiches.map((c) => _tile(c)),
            if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                child: Column(
                  children: [
                    Icon(Icons.people_outline,
                        size: 56, color: faintOf(context, Colors.black12)),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'contacts_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedOf(context, Colors.black54)),
                    ),
                  ],
                ),
              )
            // Un filtre qui ne rend rien doit le DIRE. Une liste vide sans
            // explication se lit comme « vous n'avez aucun contact ».
            else if (affiches.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Text(
                  tr(context, 'no_contact_matches', {'q': _recherche.trim()}),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedOf(context, Colors.black54)),
                ),
              ),
          ],
        ),
        if (_loading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(color: accentOf(context)),
          ),
      ],
    );
  }

  /// Les quatre actions du carnet, en cartes : créer un groupe, ajouter un
  /// contact, les listes, l'import du répertoire du téléphone.
  Widget _grilleActions() {
    final cartes = [
      _carteAction(
        icon: Icons.group_add_rounded,
        label: tr(context, 'new_group'),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewGroupScreen()),
          );
          _load();
        },
      ),
      _carteAction(
        icon: Icons.person_add_alt_1_rounded,
        label: tr(context, 'add_contact'),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
          _load();
        },
      ),
      _carteAction(
        icon: Icons.playlist_add_check_rounded,
        label: tr(context, 'contact_lists'),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ContactListsScreen()),
          );
          _load();
        },
      ),
      _carteAction(
        icon: Icons.contacts_rounded,
        label: tr(context, 'import_from_phone'),
        onTap: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PhoneSyncScreen()),
          );
          if (added == true) _load();
        },
      ),
    ];
    return Column(
      children: [
        Row(children: [
          Expanded(child: cartes[0]),
          const SizedBox(width: 12),
          Expanded(child: cartes[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cartes[2]),
          const SizedBox(width: 12),
          Expanded(child: cartes[3]),
        ]),
      ],
    );
  }

  Widget _carteAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final teinte = accentOf(context);
    /*
     * ⚠️ OPAQUE (user, 10/10/2026) : une teinte transparente laissait voir ce
     * qu'il y a dessous. La couleur d'accent est MÉLANGÉE à la surface au lieu
     * d'être posée par transparence.
     */
    return Material(
      color: Color.alphaBlend(teinte.withValues(alpha: 0.10), Theme.of(context).colorScheme.surface),
      elevation: 0.5,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 84,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: teinte, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: teinte, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titreSection(String texte) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        texte,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: mutedOf(context, Colors.black54)),
      ),
    );
  }

  /// Vide le filtre (la croix du champ).
  void _viderRecherche() {
    _rechercheCtrl.clear();
    setState(() => _recherche = "");
  }

  Widget _champRecherche() {
    final teinte = accentOf(context);
    return TextField(
      controller: _rechercheCtrl,
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() => _recherche = v),
      decoration: InputDecoration(
        isDense: true,
        hintText: tr(context, 'search_contact'),
        prefixIcon: Icon(Icons.search, color: mutedOf(context, Colors.black54)),
        suffixIcon: _recherche.isEmpty
            ? null
            : IconButton(
                tooltip: tr(context, 'search_close'),
                icon: const Icon(Icons.close),
                onPressed: _viderRecherche,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: teinte.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: teinte, width: 1.5),
        ),
      ),
    );
  }

  /// « Moi » — mes notes personnelles, le pendant du « Message yourself » de
  /// WhatsApp.
  ///
  /// ⚠️ Placée parmi les ACTIONS et non parmi les contacts : je ne suis pas une
  /// entrée de mon propre carnet d'adresses, et l'y mettre l'aurait fait
  /// remonter ou descendre au gré du tri alphabétique, à une place différente
  /// pour chaque utilisateur.
  ///
  /// La conversation est créée à la demande, en passant MON PROPRE numéro à la
  /// route de conversation directe. C'est le serveur qui reconnaît le cas et
  /// crée une conversation à un seul participant — voir
  /// `findOrCreateSelfConversation`. Le client n'a aucune règle à connaître.
  ///
  /// 🐛 **ELLE PORTAIT UN SIGNET, PAS MA PHOTO** (signalé le 19/08/2026). Elle
  /// passait par [_actionTile], dont la vignette est une icône sur fond de
  /// couleur — juste pour « Ajouter un contact », faux pour moi : je suis une
  /// PERSONNE dans cette liste, la seule qui ait un visage connu de l'appareil.
  /// Elle a donc son propre `ListTile` avec un [AvatarCircle], qui sait déjà
  /// retomber sur l'initiale quand aucune photo n'est posée.
  Widget _tuileMoi() {
    final moi = context.read<AuthController>().user;
    if (moi == null) return const SizedBox.shrink();
    return ListTile(
      leading: AvatarCircle(
        name: moi.nom ?? moi.pseudo ?? tr(context, 'home_me'),
        avatarUrl: moi.avatarUrl,
        radius: 22,
        backgroundColor: themed(context,
            light: AlanyaColors.indigo, dark: AlanyaColors.indigoLight),
      ),
      title: Text(tr(context, 'me_you'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        tr(context, 'me_notes_sub'),
        style: TextStyle(color: mutedOf(context, Colors.black54), fontSize: 13),
      ),
      onTap: () => _ouvrirMesNotes(moi),
    );
  }

  Future<void> _ouvrirMesNotes(AuthUser moi) async {
    final chat = context.read<ChatRepository>();
    try {
      final convId = await chat.createDirect(moi.publicNumber);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: tr(context, 'me_you'),
            avatarUrl: moi.avatarUrl,
            // ⚠️ `otherUserId` vaut MON identifiant, faute de correspondant.
            // C'est cohérent : dans mes notes, l'autre bout, c'est moi.
            otherUserId: moi.id,
            otherPublicNumber: moi.publicNumber,
          ),
        ),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    }
  }

  Widget _tile(Contact c) {
    return ListTile(
      leading: AvatarCircle(
        name: c.displayName,
        avatarUrl: c.avatarUrl,
        radius: 22,
        backgroundColor: c.isBlocked
            ? themed(context,
                light: Colors.grey, dark: surfacesOf(context).surfaceHaute)
            : AlanyaColors.gold,
      ),
      title: Text(c.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          tr(context, 'home_alanya_id',
                  {'id': formatAlanyaId(c.publicNumber)}) +
              (c.isBlocked ? tr(context, 'suffix_blocked') : ''),
          style: alanyaIdStyleOf(context)),
      onTap: c.isBlocked ? null : () => _startChat(c),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == "chat") _startChat(c);
          if (v == "block") _toggleBlock(c);
          if (v == "delete") _remove(c);
        },
        itemBuilder: (_) => [
          if (!c.isBlocked)
            PopupMenuItem(value: "chat", child: Text(tr(context, 'chat_action'))),
          PopupMenuItem(
              value: "block",
              child: Text(c.isBlocked ? tr(context, 'unblock') : tr(context, 'block'))),
          PopupMenuItem(value: "delete", child: Text(tr(context, 'delete'))),
        ],
      ),
    );
  }
}
