import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../contacts_repository.dart';

/// Ajout d'un contact + démarrage d'une discussion (style WhatsApp).
///
/// Formulaire simple : nom (optionnel) + numéro Alanya à 6 ou 8 chiffres + bouton
/// « Enregistrer ». Si le numéro n'existe pas, on affiche une erreur claire.
/// Si l'utilisateur est déjà un contact, on ouvre directement le chat.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  bool _saving = false;
  String? _numberError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  bool get _isNumberValid =>
      (_numberCtrl.text.trim().length == 6 || _numberCtrl.text.trim().length == 8) &&
      RegExp(r'^(\d{6}|\d{8})$').hasMatch(_numberCtrl.text.trim());

  /// Enregistrer le contact puis ouvrir la discussion.
  Future<void> _save() async {
    final number = _numberCtrl.text.trim();

    // Validation locale du numéro.
    if (!_isNumberValid) {
      setState(() => _numberError = "Le numéro Alanya doit comporter 6 ou 8 chiffres");
      return;
    }
    setState(() {
      _numberError = null;
      _saving = true;
    });

    final contacts = context.read<ContactsRepository>();
    final chat = context.read<ChatRepository>();
    final alias = _nameCtrl.text.trim();

    try {
      // 1) Vérifie que le numéro correspond à un utilisateur réel.
      final user = await contacts.searchByNumber(number);

      // 2) Ajoute aux contacts si ce n'est pas déjà fait (avec alias si fourni).
      if (!user.alreadyContact) {
        await contacts.add(number, alias: alias.isEmpty ? null : alias);
        if (mounted) showAppSnackBar("Contact enregistré ✓");
      }

      // 3) Crée (ou récupère) la conversation et l'ouvre.
      final convId = await chat.createDirect(number);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: alias.isNotEmpty ? alias : (user.pseudo ?? number),
            avatarUrl: user.avatarUrl,
            otherUserId: user.id,
            otherPublicNumber: user.publicNumber,
            otherStatusMsg: user.statusMsg,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.statusCode == 404) {
        setState(() => _numberError = "Aucun utilisateur avec ce numéro Alanya");
      } else if (e.code == 'ALREADY_CONTACT') {
        // Déjà contact : on ouvre quand même la discussion.
        try {
          final convId = await chat.createDirect(number);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(convId: convId, title: alias.isNotEmpty ? alias : number),
            ),
          );
        } catch (_) {
          showAppSnackBar("Impossible d'ouvrir la discussion");
        }
      } else {
        showAppSnackBar(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar("Enregistrement impossible. Vérifie ta connexion.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Ajouter un contact"),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Avatar placeholder ---
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.fabPrimary,
                  child: const Icon(Icons.person_add, size: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),

              // --- Champ nom ---
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Nom du contact",
                  hintText: "Ex. Marie, Papa, Collègue…",
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              // --- Champ numéro Alanya ---
              TextField(
                controller: _numberCtrl,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: "Numéro Alanya",
                  hintText: "6 ou 8 chiffres",
                  prefixIcon: const Icon(Icons.tag),
                  counterText: "",
                  errorText: _numberError,
                ),
                onChanged: (_) {
                  if (_numberError != null) setState(() => _numberError = null);
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              const Text(
                "Le numéro Alanya est un identifiant public à 6 chiffres "
                "que chaque utilisateur reçoit à l'inscription.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 32),

              // --- Bouton Enregistrer ---
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? "Enregistrement…" : "Enregistrer"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
