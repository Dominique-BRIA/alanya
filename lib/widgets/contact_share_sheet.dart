import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/contacts/contacts_repository.dart';
import '../models/contact.dart' as modele;
import '../models/message_payload.dart';
import '../theme/alanya_theme.dart';
import 'avatar_circle.dart';

/// Ce que l'écran de discussion doit envoyer après la sélection.
///
/// Type dédié (et non une `List<SharedContact>`) parce que la feuille de médias
/// rend des résultats de natures différentes par le même `Navigator.pop` :
/// l'écran de discussion distingue les cas par leur type.
class ContactShareResult {
  final List<SharedContact> contacts;
  const ContactShareResult({required this.contacts});
}

/// Sélecteur des contacts **Alanya** à partager dans une discussion.
///
/// ⚠️ Uniquement des contacts Alanya, c'est-à-dire porteurs d'un Alanya ID —
/// règle rappelée par le user le 17/08/2026. C'est ce qui donne son intérêt à la
/// fiche reçue : le destinataire peut écrire, appeler et ajouter la personne
/// DANS l'application. Un contact tiré du répertoire téléphonique ne
/// porterait qu'un nom et un numéro inutilisables ici.
class ContactShareSheet extends StatefulWidget {
  const ContactShareSheet({super.key});

  static Future<ContactShareResult?> show(BuildContext context) {
    return showModalBottomSheet<ContactShareResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ContactShareSheet(),
    );
  }

  @override
  State<ContactShareSheet> createState() => _ContactShareSheetState();
}

class _ContactShareSheetState extends State<ContactShareSheet> {
  List<modele.Contact>? _contacts;
  bool _chargement = true;
  String? _erreur;

  final Set<String> _retenus = {}; // Alanya ID des contacts choisis
  String _recherche = '';

  /// Plafond aligné sur celui du serveur (10 par charge) : bloquer la sélection
  /// vaut mieux que laisser envoyer puis échouer à l'arrivée.
  static const int _maxContacts = 10;

  @override
  void initState() {
    super.initState();
    _charge();
  }

  Future<void> _charge() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final contacts = await context.read<ContactsRepository>().list();
      if (!mounted) return;
      final utiles = contacts.where((c) => !c.isBlocked).toList()
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      setState(() {
        _contacts = utiles;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Impossible de charger les contacts";
      });
    }
  }

  void _bascule(modele.Contact c) {
    setState(() {
      if (_retenus.contains(c.publicNumber)) {
        _retenus.remove(c.publicNumber);
      } else {
        if (_retenus.length >= _maxContacts) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("10 contacts au maximum par message")),
          );
          return;
        }
        _retenus.add(c.publicNumber);
      }
    });
  }

  void _envoyer() {
    if (_retenus.isEmpty) return;
    final source = _contacts ?? const <modele.Contact>[];
    // Ordre de la LISTE, et non ordre de sélection : c'est celui que
    // l'utilisateur voit à l'écran au moment où il valide.
    final charges = source
        .where((c) => _retenus.contains(c.publicNumber))
        .map((c) => SharedContact(
              name: c.displayName,
              phones: [c.publicNumber],
              alanyaId: c.publicNumber,
              avatarUrl: c.avatarUrl,
            ))
        .toList();
    if (charges.isEmpty) return;
    Navigator.of(context).pop(ContactShareResult(contacts: charges));
  }

  List<modele.Contact> get _liste {
    final source = _contacts ?? const <modele.Contact>[];
    if (_recherche.isEmpty) return source;
    final q = _recherche.toLowerCase();
    return source
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            c.publicNumber.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fond = dark ? surfaces.surface : Colors.white;
    final onSub = dark ? AlanyaColors.craie2 : Colors.black54;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AlanyaColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Text("Partager un contact",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _recherche = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Rechercher un contact",
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AlanyaColors.grey300)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(child: _corps(onSub)),
        if (_retenus.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _envoyer,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text("Envoyer (${_retenus.length})"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentOf(context),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _corps(Color onSub) {
    if (_chargement) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child:
            Center(child: CircularProgressIndicator(color: accentOf(context))),
      );
    }
    if (_erreur != null) {
      return _message(
        icone: Icons.cloud_off_rounded,
        texte: _erreur!,
        action: TextButton(onPressed: _charge, child: const Text("Réessayer")),
        onSub: onSub,
      );
    }

    final liste = _liste;
    if (liste.isEmpty) {
      return _message(
        icone: Icons.person_search_outlined,
        texte: _recherche.isEmpty
            ? "Aucun contact Alanya à partager"
            : "Aucun résultat",
        onSub: onSub,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: liste.length,
      itemBuilder: (_, i) {
        final c = liste[i];
        final choisi = _retenus.contains(c.publicNumber);
        return ListTile(
          onTap: () => _bascule(c),
          leading: AvatarCircle(
              name: c.displayName, avatarUrl: c.avatarUrl, radius: 20),
          title:
              Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(c.publicNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: onSub)),
          trailing: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: choisi ? accentOf(context) : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: choisi ? accentOf(context) : AlanyaColors.grey400,
                  width: 1.5),
            ),
            child: choisi
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        );
      },
    );
  }

  Widget _message({
    required IconData icone,
    required String texte,
    required Color onSub,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, size: 44, color: AlanyaColors.grey400),
        const SizedBox(height: 10),
        Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: onSub)),
        if (action != null) ...[const SizedBox(height: 4), action],
      ]),
    );
  }
}
