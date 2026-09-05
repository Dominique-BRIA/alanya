import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
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
      if (!mounted) return;
      showAppSnackBar(tr(context, 'add_done'));
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
      }
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
