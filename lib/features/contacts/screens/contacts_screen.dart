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
import '../../../widgets/motif_background.dart';
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

  /// La barre de recherche occupe-t-elle l'en-tête ?
  ///
  /// ⚠️ ELLE A DÉMÉNAGÉ (demande du user, 19/08/2026). Elle vivait dans la
  /// liste défilante, sous les actions rapides : il fallait donc remonter tout
  /// en haut pour chercher, et sur un carnet un peu fourni elle était
  /// simplement invisible. Elle est désormais dans l'en-tête, ouverte par une
  /// loupe posée juste avant le bouton d'import — la disposition de WhatsApp.
  bool _enRecherche = false;

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
    final filtres = _recherche.trim().isEmpty
        ? List<Contact>.from(tous)
        : tous
            .where((c) =>
                contientRecherche(c.displayName, _recherche) ||
                c.publicNumber.contains(stripAlanyaId(_recherche)))
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(
        context,
        tr(context, 'contacts_title'),
        titreWidget: _enRecherche ? _champRecherche() : null,
        actions: _enRecherche
            ? [
                IconButton(
                  tooltip: tr(context, 'search_close'),
                  icon: const Icon(Icons.close),
                  onPressed: _fermerRecherche,
                ),
              ]
            : [
                // La loupe précède l'import, comme sur WhatsApp : c'est le
                // geste le plus fréquent du carnet, il tombe donc sous le
                // pouce avant celui qu'on ne fait qu'une fois.
                IconButton(
                  tooltip: tr(context, 'search'),
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _enRecherche = true),
                ),
                // Synchronisation depuis le répertoire téléphonique
                IconButton(
                  tooltip: tr(context, 'import_from_phone'),
                  icon: const Icon(Icons.contacts_outlined),
                  onPressed: () async {
                    final added = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const PhoneSyncScreen()),
                    );
                    if (added == true) _load();
                  },
                ),
                // Bouton actualiser toujours visible
                IconButton(
                  tooltip: tr(context, 'refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load,
                ),
              ],
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
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
    if (contacts.isEmpty) {
      return ListView(
        children: [
          // --- Actions rapides (visibles même si aucun contact) ---
          _actionTile(
            icon: Icons.group_add,
            color: themed(context,
                light: AlanyaColors.forest, dark: AlanyaColors.indigoLight),
            title: tr(context, 'new_group'),
            subtitle: tr(context, 'new_group_sub'),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewGroupScreen()),
              );
              _load();
            },
          ),
          const Divider(height: 1),
          _actionTile(
            icon: Icons.person_add,
            color: accentOf(context),
            title: tr(context, 'add_contact'),
            subtitle: tr(context, 'add_contact_sub'),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              );
              _load();
            },
          ),

          Divider(height: 1, thickness: 8, color: surfacesOf(context).fond),
          // --- Message d'état vide ---
          const SizedBox(height: 60),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        ListView(
          children: [
            // --- Actions rapides (style WhatsApp) ---
            _actionTile(
              icon: Icons.group_add,
              color: themed(context,
                  light: AlanyaColors.forest, dark: AlanyaColors.indigoLight),
              title: tr(context, 'new_group'),
              subtitle: tr(context, 'new_group_sub'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewGroupScreen()),
                );
                _load();
              },
            ),
            const Divider(height: 1),
            _actionTile(
              icon: Icons.person_add,
              color: accentOf(context),
              title: tr(context, 'add_contact'),
              subtitle: tr(context, 'add_contact_sub'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewChatScreen()),
                );
                _load();
              },
            ),

            const Divider(height: 1),
            _actionTile(
              icon: Icons.playlist_add_check,
              color: AlanyaColors.gold,
              title: tr(context, 'contact_lists'),
              subtitle: tr(context, 'contact_lists_sub'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ContactListsScreen()),
                );
                _load();
              },
            ),
            const Divider(height: 1),
            _tuileMoi(),

            Divider(height: 1, thickness: 8, color: surfacesOf(context).fond),
            // --- Liste des contacts, filtrée et classée ---
            ...affiches.map((c) => _tile(c)),
            // Un filtre qui ne rend rien doit le DIRE. Une liste vide sans
            // explication se lit comme « vous n'avez aucun contact ».
            if (affiches.isEmpty)
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

  /// Ferme la recherche ET vide le filtre.
  ///
  /// Les deux ensemble, toujours : refermer la barre en laissant le filtre
  /// actif donnerait un carnet amputé sans plus rien à l'écran pour l'expliquer.
  void _fermerRecherche() {
    _rechercheCtrl.clear();
    setState(() {
      _recherche = "";
      _enRecherche = false;
    });
  }

  Widget _champRecherche() {
    return TextField(
      controller: _rechercheCtrl,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() => _recherche = v),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: tr(context, 'search_contact'),
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

  /// Tuile d'action rapide (style WhatsApp) placée au-dessus de la liste.
  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      onTap: onTap,
    );
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
