import 'package:flutter/material.dart';
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
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

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
  void dispose() {
    _numberCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    // On nettoie AVANT de valider : l'utilisateur peut coller un ID formaté
    // (« 67 64 15 99 »), qui serait sinon rejeté comme invalide.
    final number = stripAlanyaId(_numberCtrl.text);
    if (!RegExp(r'^(\d{6}|\d{8})$').hasMatch(number)) {
      setState(() => _error = "Entre un Alanya ID valide (6 ou 8 chiffres)");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await context.read<ContactsRepository>().searchByNumber(number);
      if (!mounted) return;
      setState(() => _result = res);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 404
          ? "Aucun utilisateur avec cet Alanya ID"
          : "Erreur ${e.statusCode} : ${e.message}");
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Recherche impossible. Vérifie ta connexion.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(UserSearchResult user) async {
    if (user.alreadyContact) {
      showAppSnackBar("${user.pseudo ?? formatAlanyaId(user.publicNumber)} est déjà dans tes contacts");
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final alias = _aliasCtrl.text.trim();
      await context.read<ContactsRepository>().add(
            user.publicNumber,
            alias: alias.isEmpty ? null : alias,
          );
      if (!mounted) return;
      showAppSnackBar("Contact ajouté ✓");
      Navigator.of(context).pop(true); // signale que la liste doit se recharger
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      showAppSnackBar(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Impossible d'ajouter ce contact. Vérifie ta connexion.");
      showAppSnackBar("Erreur inattendue");
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
        await contacts.add(user.publicNumber, alias: alias.isEmpty ? null : alias);
      }
      final convId = await context.read<ChatRepository>().createDirect(user.publicNumber);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: alias.isNotEmpty ? alias : (user.pseudo ?? user.publicNumber),
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
      showAppSnackBar("Impossible d'ouvrir la discussion");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Ajouter un contact"),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Alanya ID",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "Chaque utilisateur reçoit un Alanya ID public à 6 ou 8 chiffres à l'inscription.",
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
                      decoration: const InputDecoration(
                        labelText: "Alanya ID (6 ou 8 chiffres)",
                        hintText: "67 64 15 99",
                        counterText: "",
                        prefixIcon: Icon(Icons.tag),
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
                  child: Center(child: CircularProgressIndicator(color: accentOf(context))),
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
    final name = user.pseudo ?? "Utilisateur ${formatAlanyaId(user.publicNumber)}";
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: themed(context, light: AlanyaColors.sand, dark: AlanyaColors.ligne)),
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
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text("Alanya ID : ${formatAlanyaId(user.publicNumber)}", style: TextStyle(color: mutedOf(context, Colors.black54))),
                      if (user.alreadyContact)
                        Text(
                          "Déjà dans ton répertoire",
                          style: TextStyle(color: themed(context, light: AlanyaColors.forest, dark: AlanyaColors.indigoLight), fontSize: 12),
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
                decoration: const InputDecoration(
                  labelText: "Nom dans ton répertoire (optionnel)",
                  hintText: "Ex. Marie, Papa, Collègue…",
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () => user.alreadyContact ? _addAndChat(user) : _add(user),
              child: Text(user.alreadyContact ? "Discuter" : "Ajouter au répertoire"),
            ),
            if (!user.alreadyContact) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _loading ? null : () => _addAndChat(user),
                child: const Text("Ajouter et discuter"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
