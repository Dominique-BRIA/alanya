import 'package:flutter/material.dart';
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
            ? "Erreur ${e.statusCode} : ${e.message}"
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = (_contacts?.isEmpty ?? true)
            ? "Impossible de charger les contacts.\nVérifie ta connexion."
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
      _snack("Impossible d'ouvrir la discussion");
    }
  }

  Future<void> _toggleBlock(Contact c) async {
    try {
      await context.read<ContactsRepository>().setBlocked(c.id, !c.isBlocked);
      await _load();
    } catch (_) {
      _snack("Action impossible");
    }
  }

  Future<void> _remove(Contact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Supprimer le contact ?"),
        content: Text("${c.displayName} sera retiré de ton répertoire."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Supprimer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<ContactsRepository>().remove(c.id);
      await _load();
    } catch (_) {
      _snack("Suppression impossible");
    }
  }

  void _snack(String m) => showAppSnackBar(m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(
        context,
        "Contacts",
        actions: [
          // Synchronisation depuis le répertoire téléphonique
          IconButton(
            tooltip: "Importer depuis le téléphone",
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
            tooltip: "Actualiser",
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
                    label: const Text("Réessayer"),
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
            title: "Nouveau groupe",
            subtitle: "Créer un groupe avec des contacts",
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
            title: "Ajouter un contact",
            subtitle: "Rechercher par Alanya ID",
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
                    "Aucun contact pour l'instant.\nUtilise les options ci-dessus pour en ajouter.",
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
              title: "Nouveau groupe",
              subtitle: "Créer un groupe avec des contacts",
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
              title: "Ajouter un contact",
              subtitle: "Rechercher par Alanya ID",
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewChatScreen()),
                );
                _load();
              },
            ),

            const Divider(height: 1),
            _tuileMoi(),

            Divider(height: 1, thickness: 8, color: surfacesOf(context).fond),
            _barreRecherche(),
            // --- Liste des contacts, filtrée et classée ---
            ...affiches.map((c) => _tile(c)),
            // Un filtre qui ne rend rien doit le DIRE. Une liste vide sans
            // explication se lit comme « vous n'avez aucun contact ».
            if (affiches.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Text(
                  "Aucun contact ne correspond à « ${_recherche.trim()} ».",
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

  /// Barre de recherche du carnet d'adresses.
  ///
  /// ⚠️ Elle vit DANS la liste défilante, et non dans une barre figée : le
  /// carnet se parcourt au pouce, et une barre collée en haut mangerait une
  /// ligne de contacts en permanence pour un usage occasionnel.
  Widget _barreRecherche() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        controller: _rechercheCtrl,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _recherche = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: "Rechercher un contact",
          prefixIcon: const Icon(Icons.search, size: 20),
          // La croix n'apparaît que s'il y a quelque chose à effacer : un
          // bouton toujours visible mais sans effet apprend à être ignoré.
          suffixIcon: _recherche.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _rechercheCtrl.clear();
                    setState(() => _recherche = "");
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: surfacesOf(context).surfaceHaute,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
  Widget _tuileMoi() {
    final moi = context.read<AuthController>().user;
    if (moi == null) return const SizedBox.shrink();
    return _actionTile(
      icon: Icons.bookmark_outline,
      color: themed(context,
          light: AlanyaColors.indigo, dark: AlanyaColors.indigoLight),
      title: "Moi (vous)",
      subtitle: "Notes personnelles, brouillons, liens à garder",
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
            title: "Moi (vous)",
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
          "Alanya ID : ${formatAlanyaId(c.publicNumber)}${c.isBlocked ? " · bloqué" : ""}",
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
            const PopupMenuItem(value: "chat", child: Text("Discuter")),
          PopupMenuItem(
              value: "block",
              child: Text(c.isBlocked ? "Débloquer" : "Bloquer")),
          const PopupMenuItem(value: "delete", child: Text("Supprimer")),
        ],
      ),
    );
  }
}
