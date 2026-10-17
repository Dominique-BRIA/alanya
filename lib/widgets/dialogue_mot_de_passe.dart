import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Demande le mot de passe du compte avant d'ouvrir un écran sensible.
///
/// Rend le mot de passe SAISI ET VÉRIFIÉ, ou `null` si la personne renonce.
///
/// 🔴 LA VÉRIFICATION SE FAIT DANS LE DIALOGUE, pas après sa fermeture. Une
/// porte qui laisse entrer n'importe quelle saisie et ne dit non qu'au moment
/// d'enregistrer n'arrête personne : elle fait juste perdre un formulaire déjà
/// rempli. [verifier] doit donc lever si le mot de passe est faux — l'écran
/// reste ouvert et l'erreur s'affiche dedans, sous le champ.
///
/// ⚠️ CE N'EST PAS CE QUI PROTÈGE. La route qui écrit redemande le mot de passe
/// pour son propre compte ; un client modifié peut sauter ce dialogue. Il sert
/// à empêcher un téléphone déverrouillé posé sur une table d'aller plus loin,
/// et à dire non tout de suite.
Future<String?> demanderMotDePasse(
  BuildContext context, {
  required String message,
  required Future<void> Function(String motDePasse) verifier,
}) {
  return showDialog<String>(
    context: context,
    // Le dialogue ne se ferme pas d'un appui à côté : on y entre pour une
    // raison, et le fermer par accident renvoie à l'écran précédent sans rien
    // dire.
    barrierDismissible: false,
    builder: (_) => _DialogueMotDePasse(message: message, verifier: verifier),
  );
}

class _DialogueMotDePasse extends StatefulWidget {
  const _DialogueMotDePasse({required this.message, required this.verifier});

  final String message;
  final Future<void> Function(String motDePasse) verifier;

  @override
  State<_DialogueMotDePasse> createState() => _DialogueMotDePasseState();
}

class _DialogueMotDePasseState extends State<_DialogueMotDePasse> {
  final _ctrl = TextEditingController();
  bool _envoi = false;
  bool _cache = true;
  String? _erreur;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    // Sans trim : un espace final fait partie du mot de passe.
    final mdp = _ctrl.text;
    if (mdp.isEmpty) {
      setState(() => _erreur = tr(context, 'password_required'));
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await widget.verifier(mdp);
      if (!mounted) return;
      Navigator.of(context).pop(mdp);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        // Le message vient du serveur : « Mot de passe incorrect », ou la
        // limite d'essais. Le remplacer par un texte générique cacherait le
        // 429, et la personne réessaierait sans comprendre pourquoi ça
        // refuse un mot de passe juste.
        _erreur = e is Exception ? _messageDe(e) : tr(context, 'server_unreachable');
      });
    }
  }

  String _messageDe(Exception e) {
    final brut = e.toString();
    // `ApiException.toString()` porte déjà le message lisible du serveur ; le
    // préfixe de type, lui, n'a rien à faire sous un champ de saisie.
    final sansPrefixe = brut.replaceFirst(RegExp(r"^[A-Za-z]*Exception:\s*"), "");
    return sansPrefixe.isEmpty ? tr(context, 'server_unreachable') : sansPrefixe;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'password_gate_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: _cache,
            autofocus: true,
            enabled: !_envoi,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _valider(),
            decoration: InputDecoration(
              labelText: tr(context, 'current_password'),
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: _erreur,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(_cache ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _cache = !_cache),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _envoi ? null : _valider,
          child: _envoi
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(tr(context, 'continue')),
        ),
      ],
    );
  }
}
