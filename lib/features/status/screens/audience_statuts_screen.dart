import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../models/contact.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../contacts/contacts_repository.dart';
import '../status_repository.dart';

/// « Qui peut voir mes statuts » — les trois audiences de WhatsApp.
///
/// ⚠️ LA LISTE EST COMMUNE AUX DEUX MODES QUI EN ONT UNE. Passer de « Mes
/// contacts sauf… » à « Partager avec… » CONSERVE les personnes déjà cochées,
/// exactement comme WhatsApp : c'est souvent la même poignée de gens qu'on veut
/// désigner, dans un sens ou dans l'autre. Le sens de lecture, lui, s'inverse —
/// d'où le libellé qui change sous chaque mode.
class AudienceStatutsScreen extends StatefulWidget {
  const AudienceStatutsScreen({super.key});

  @override
  State<AudienceStatutsScreen> createState() => _AudienceStatutsScreenState();
}

class _AudienceStatutsScreenState extends State<AudienceStatutsScreen> {
  String _mode = ModeAudience.mesContacts;
  Set<String> _choisis = {};
  List<Contact> _contacts = [];
  bool _chargement = true;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _charge();
  }

  Future<void> _charge() async {
    try {
      final repo = context.read<StatusRepository>();
      final contacts = context.read<ContactsRepository>();
      // Les deux en parallèle : l'écran n'a rien à montrer tant qu'il manque
      // l'un des deux.
      final resultats = await Future.wait([repo.audience(), contacts.list()]);
      if (!mounted) return;
      final audience = resultats[0] as AudienceStatuts;
      setState(() {
        _mode = audience.mode;
        _choisis = audience.userIds.toSet();
        _contacts = resultats[1] as List<Contact>;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _chargement = false);
      showAppSnackBar("Chargement impossible. Réessaie.");
    }
  }

  /// Enregistre l'état complet, et REVIENT EN ARRIÈRE en cas d'échec.
  ///
  /// ⚠️ Un réglage de confidentialité qui semble pris alors qu'il ne l'est pas
  /// est pire que pas de réglage du tout : l'utilisateur croirait avoir
  /// restreint son audience.
  Future<void> _enregistre(String mode, Set<String> choisis) async {
    final ancienMode = _mode;
    final anciensChoisis = _choisis;
    setState(() {
      _mode = mode;
      _choisis = choisis;
      _enregistrement = true;
    });
    try {
      await context.read<StatusRepository>().setAudience(
        mode,
        choisis.toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mode = ancienMode;
        _choisis = anciensChoisis;
      });
      showAppSnackBar("Échec de l'enregistrement. Rien n'a été modifié.");
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  String get _libelleListe => switch (_mode) {
    ModeAudience.mesContactsSauf => "Exclure des contacts",
    ModeAudience.partagerAvec => "Partager avec…",
    _ => "",
  };

  String get _sousTitreListe {
    final n = _choisis.length;
    if (n == 0) {
      return _mode == ModeAudience.partagerAvec
          // Une liste vide en mode « Partager avec… » veut dire PERSONNE. Le
          // dire franchement : c'est le seul réglage qui coupe tout.
          ? "Personne pour l'instant — tes statuts ne sont visibles par personne"
          : "Aucune exclusion";
    }
    return "$n personne${n > 1 ? 's' : ''}";
  }

  Future<void> _choisirPersonnes() async {
    final selection = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => _ChoixPersonnes(
          titre: _libelleListe,
          contacts: _contacts,
          initiale: _choisis,
        ),
      ),
    );
    if (selection == null) return;
    await _enregistre(_mode, selection);
  }

  @override
  Widget build(BuildContext context) {
    final muted = themed(
      context,
      light: AlanyaColors.grey500,
      dark: AlanyaColors.craie2,
    );
    return Scaffold(
      appBar: backAppBar(context, "Statut"),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "Qui peut voir mes statuts",
                    style: TextStyle(color: muted, fontWeight: FontWeight.bold),
                  ),
                ),
                _choix(
                  ModeAudience.mesContacts,
                  "Mes contacts",
                  "Toutes les personnes qui t'ont dans leurs contacts.",
                ),
                _choix(
                  ModeAudience.mesContactsSauf,
                  "Mes contacts sauf…",
                  "Tes contacts, moins ceux que tu exclus.",
                ),
                _choix(
                  ModeAudience.partagerAvec,
                  "Partager avec…",
                  "Uniquement les personnes que tu désignes.",
                ),
                if (_mode != ModeAudience.mesContacts) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _mode == ModeAudience.partagerAvec
                          ? Icons.person_add_alt
                          : Icons.person_remove_alt_1,
                      color: themed(
                        context,
                        light: AlanyaColors.terracotta,
                        dark: AlanyaColors.terracottaNuit,
                      ),
                    ),
                    title: Text(_libelleListe),
                    subtitle: Text(_sousTitreListe),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: _enregistrement ? null : _choisirPersonnes,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "Ce réglage s'applique aussi à tes statuts déjà publiés. "
                    "Une personne bloquée ne voit jamais tes statuts, quel que "
                    "soit le mode choisi.",
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
    );
  }

  /// Une coche plutôt qu'un bouton radio : c'est ce que fait déjà l'écran
  /// « Vu à et en ligne », juste à côté, et les deux doivent se ressembler.
  Widget _choix(String mode, String titre, String detail) {
    final actif = _mode == mode;
    return ListTile(
      title: Text(titre),
      subtitle: Text(detail),
      trailing: actif
          ? Icon(
              Icons.check,
              color: themed(
                context,
                light: AlanyaColors.forest,
                dark: AlanyaColors.terracottaNuit,
              ),
            )
          : null,
      // La liste est conservée d'un mode à l'autre — voir la note de tête.
      onTap: _enregistrement ? null : () => _enregistre(mode, _choisis),
    );
  }
}

/// Sélection multiple parmi MES CONTACTS, avec recherche.
///
/// ⚠️ CE N'EST PAS `ContactPickerSheet`, et c'est délibéré : celui-ci sert à
/// AJOUTER des numéros, y compris inconnus du répertoire, et ne sait pas partir
/// d'une sélection déjà cochée. Ici on part toujours d'un état existant, et un
/// numéro hors répertoire n'aurait aucun sens — l'audience se règle sur des
/// comptes, pas sur des numéros.
class _ChoixPersonnes extends StatefulWidget {
  const _ChoixPersonnes({
    required this.titre,
    required this.contacts,
    required this.initiale,
  });

  final String titre;
  final List<Contact> contacts;
  final Set<String> initiale;

  @override
  State<_ChoixPersonnes> createState() => _ChoixPersonnesState();
}

class _ChoixPersonnesState extends State<_ChoixPersonnes> {
  late final Set<String> _coches = {...widget.initiale};
  String _recherche = "";

  @override
  Widget build(BuildContext context) {
    final q = _recherche.trim().toLowerCase();
    final visibles = q.isEmpty
        ? widget.contacts
        : widget.contacts
              .where(
                (c) =>
                    c.displayName.toLowerCase().contains(q) ||
                    c.publicNumber.contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_coches),
            child: const Text("OK"),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Rechercher",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _recherche = v),
            ),
          ),
          Expanded(
            child: visibles.isEmpty
                ? const Center(child: Text("Aucun contact"))
                : ListView.builder(
                    itemCount: visibles.length,
                    itemBuilder: (_, i) {
                      final c = visibles[i];
                      return CheckboxListTile(
                        value: _coches.contains(c.userId),
                        onChanged: (v) => setState(() {
                          // ⚠️ `userId` et NON `id` : `id` est celui de la
                          // ligne de répertoire, pas celui du compte.
                          if (v == true) {
                            _coches.add(c.userId);
                          } else {
                            _coches.remove(c.userId);
                          }
                        }),
                        secondary: AvatarCircle(
                          name: c.displayName,
                          avatarUrl: c.avatarUrl,
                          radius: 20,
                        ),
                        title: Text(c.displayName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
