import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/sonneries_listes.dart';
import '../../../models/contact_list.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../contact_lists_repository.dart';
import '../contacts_repository.dart';

/// Recherche par Alanya ID (6 chiffres) puis ajout au répertoire.
///
/// [initialNumber] pré-remplit le champ et lance la recherche : le clavier
/// d'appel arrive ici avec l'ID déjà composé, le retaper serait absurde.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key, this.initialNumber});

  final String? initialNumber;

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _numberCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  bool _loading = false;
  UserSearchResult? _result;
  String? _error;

  /// Les listes du compte, pour ranger le contact dès son ajout.
  ///
  /// ⚠️ CHARGÉES EN SILENCE, ET LEUR ABSENCE NE BLOQUE RIEN. Ranger dans une
  /// liste est un confort ; ajouter un contact est le but de l'écran. Un
  /// catalogue injoignable fait disparaître le choix, rien d'autre.
  List<ListeContacts> _listes = const [];

  /// La liste choisie, ou `null` pour n'en choisir aucune.
  String? _listeChoisie;

  @override
  void initState() {
    super.initState();
    final initial = stripAlanyaId(widget.initialNumber ?? "");
    if (initial.isEmpty) return;
    _numberCtrl.text = formatAlanyaId(initial);
    // Après la première frame : _search() touche à l'état et lit le Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ici et non dans `initState` : lire un Provider y est trop tôt. Le drapeau
    // évite de recharger à chaque changement de dépendance.
    if (_listesDemandees) return;
    _listesDemandees = true;
    _chargerListes();
  }

  bool _listesDemandees = false;

  Future<void> _chargerListes() async {
    try {
      final l = await context.read<ContactListsRepository>().list();
      if (mounted) setState(() => _listes = l);
    } catch (_) {
      // Silencieux : voir la note sur `_listes`.
    }
  }

  /// Range le nouveau contact dans la liste choisie, s'il y en a une.
  ///
  /// ⚠️ `memberIds` REMPLACE l'ensemble des membres, il n'ajoute pas — c'est le
  /// contrat du serveur, rappelé par `ContactListsRepository.modifier`. Il faut
  /// donc RELIRE la liste juste avant, et renvoyer l'ensemble complet. Envoyer
  /// le seul nouvel identifiant viderait la liste de tous ses autres membres.
  ///
  /// ⚠️ Entre cette relecture et l'écriture, un autre appareil pourrait modifier
  /// la même liste : sa modification serait alors perdue. La fenêtre se compte
  /// en millisecondes et le contrat du serveur ne permet pas de faire mieux —
  /// c'est un remplacement, pas un ajout.
  ///
  /// Rend `true` si le rangement a eu lieu (ou n'était pas demandé).
  Future<bool> _rangerDansListe(String userId) async {
    final id = _listeChoisie;
    if (id == null) return true;
    try {
      final depot = context.read<ContactListsRepository>();
      final fraiches = await depot.list();
      ListeContacts? cible;
      for (final l in fraiches) {
        if (l.id == id) cible = l;
      }
      if (cible == null) return false;

      final membres = <String>{...cible.members.map((m) => m.id), userId};
      final res = await depot.modifier(id, membreIds: membres.toList());
      if (!mounted) return true;
      // ⚠️ Le cache en mémoire décide de la SONNERIE d'un appel entrant : sans
      // cette mise à jour, le contact qu'on vient de ranger n'aurait la
      // sonnerie de sa liste qu'au prochain démarrage de l'application.
      context.read<SonneriesDeListes>().alimenter([
        for (final l in fraiches) l.id == id ? res.liste : l,
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    // On nettoie AVANT de valider : l'utilisateur peut coller un ID formaté
    // (« 67 64 15 99 »), qui serait sinon rejeté comme invalide.
    final number = stripAlanyaId(_numberCtrl.text);
    if (!estAlanyaIdValide(number)) {
      setState(() => _error =
          tr(context, 'add_id_invalid', {'min': '$alanyaIdMinLength', 'max': '$alanyaIdMaxLength'}));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res =
          await context.read<ContactsRepository>().searchByNumber(number);
      if (!mounted) return;
      setState(() => _result = res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 404
          ? tr(context, 'add_not_found')
          : tr(context, 'error_with_code', {'code': '${e.statusCode}', 'message': e.message}));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tr(context, 'add_search_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(UserSearchResult user) async {
    if (user.alreadyContact) {
      showAppSnackBar(
          tr(context, 'add_already_contact', {'nom': user.pseudo ?? formatAlanyaId(user.publicNumber)}));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alias = _aliasCtrl.text.trim();
      await context.read<ContactsRepository>().add(
            user.publicNumber,
            alias: alias.isEmpty ? null : alias,
          );
      final range = await _rangerDansListe(user.id);
      if (!mounted) return;
      // ⚠️ DEUX MESSAGES DISTINCTS, parce que le contact EST ajouté même si le
      // rangement échoue. Un « ajouté » seul laisserait croire que la liste a
      // été renseignée ; une erreur seule laisserait croire que rien n'a été
      // fait, et l'utilisateur recommencerait pour rien.
      showAppSnackBar(
          range ? tr(context, 'add_done') : tr(context, 'list_add_failed'));
      Navigator.of(context).pop(true); // signale que la liste doit se recharger
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      showAppSnackBar(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = tr(context, 'add_failed'));
      showAppSnackBar(tr(context, 'error_unexpected'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAndChat(UserSearchResult user) async {
    setState(() => _loading = true);
    try {
      final contacts = context.read<ContactsRepository>();
      final alias = _aliasCtrl.text.trim();
      if (!user.alreadyContact) {
        await contacts.add(user.publicNumber,
            alias: alias.isEmpty ? null : alias);
        final range = await _rangerDansListe(user.id);
        if (mounted && !range) {
          showAppSnackBar(tr(context, 'list_add_failed'));
        }
      }
      // ⚠️ Garde ANTÉRIEURE à la lecture du Provider, pas après. L'ajout du
      // contact peut avoir duré assez pour que l'écran soit quitté : `read` sur
      // un contexte démonté lève, et l'erreur ne dirait rien d'utile.
      if (!mounted) return;
      final convId =
          await context.read<ChatRepository>().createDirect(user.publicNumber);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title:
                alias.isNotEmpty ? alias : (user.pseudo ?? user.publicNumber),
            avatarUrl: user.avatarUrl,
            otherUserId: user.id,
            otherPublicNumber: user.publicNumber,
            otherStatusMsg: user.statusMsg,
          ),
        ),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'chat_open_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'add_contact')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'alanya_id'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, 'add_id_explain'),
                style: TextStyle(color: mutedOf(context, Colors.black54)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _numberCtrl,
                      keyboardType: TextInputType.number,
                      // Le plafond porte sur les chiffres, pas sur les
                      // caractères : un maxLength compterait les espaces.
                      inputFormatters: const [AlanyaIdInputFormatter()],
                      decoration: InputDecoration(
                        labelText: tr(context, 'add_id_hint'),
                        hintText: "67 64 15 99",
                        counterText: "",
                        prefixIcon: const Icon(Icons.tag),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _search,
                      child: const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: dangerOf(context))),
              ],
              if (_loading && _result == null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: accentOf(context))),
                ),
              if (_result != null) ...[
                const SizedBox(height: 20),
                _resultCard(_result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard(UserSearchResult user) {
    final name =
        user.pseudo ?? tr(context, 'user_numbered', {'id': formatAlanyaId(user.publicNumber)});
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: themed(context,
                light: AlanyaColors.sand, dark: AlanyaColors.ligne)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AlanyaColors.gold,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      Text(tr(context, 'home_alanya_id', {'id': formatAlanyaId(user.publicNumber)}),
                          style: TextStyle(
                              color: alanyaIdOf(context, Colors.black54))),
                      if (user.alreadyContact)
                        Text(
                          tr(context, 'add_already_in_book'),
                          style: TextStyle(
                              color: themed(context,
                                  light: AlanyaColors.forest,
                                  dark: AlanyaColors.indigoLight),
                              fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (!user.alreadyContact) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _aliasCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'add_local_name'),
                  hintText: tr(context, 'add_local_name_hint'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              // --- Ranger directement dans une liste ---
              //
              // ⚠️ N'APPARAÎT QUE S'IL EXISTE AU MOINS UNE LISTE. Un choix sans
              // option laisserait croire à une fonctionnalité cassée. Le cas est
              // rare — tout compte en reçoit quatre d'office — mais existe pour
              // qui les a toutes supprimées.
              if (_listes.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _listeChoisie,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'list_add_to'),
                    prefixIcon: const Icon(Icons.folder_outlined),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr(context, 'list_none')),
                    ),
                    ..._listes.map((l) => DropdownMenuItem<String?>(
                          value: l.id,
                          child: Text(l.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setState(() => _listeChoisie = v),
                ),
              ],
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () => user.alreadyContact ? _addAndChat(user) : _add(user),
              child: Text(
                  user.alreadyContact ? tr(context, 'chat_action') : tr(context, 'add_to_book')),
            ),
            if (!user.alreadyContact) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _loading ? null : () => _addAndChat(user),
                child: Text(tr(context, 'add_and_chat')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
