import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/alanya_id_formatter.dart';
import '../../../core/texte_recherche.dart';
import '../../../models/contact.dart';
import '../../../models/contact_list.dart';
import '../../../core/sonneries_listes.dart';
import '../../../models/sonnerie.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../../widgets/motif_background.dart';
import '../contact_lists_repository.dart';
import '../contacts_repository.dart';
import '../../settings/ringtones_repository.dart';
import '../teintes_listes.dart';

/// Listes de contacts personnalisées — « Famille », « Équipe », « Clients ».
///
/// Le serveur porte déjà tout le contrat (`/api/contact-lists`) : cet écran ne
/// fait que l'exposer. Deux règles y sont donc RESPECTÉES, pas réinventées :
///
///  * la mise à jour des membres REMPLACE l'ensemble, elle n'ajoute pas. On
///    envoie donc toujours la liste complète voulue ;
///  * un numéro que le serveur n'a pas su rattacher revient dans
///    `unknownNumbers`. Le taire ferait croire à un ajout réussi.
class ContactListsScreen extends StatefulWidget {
  const ContactListsScreen({super.key});

  @override
  State<ContactListsScreen> createState() => _ContactListsScreenState();
}

class _ContactListsScreenState extends State<ContactListsScreen> {
  List<ListeContacts>? _listes;
  List<Contact> _contacts = const [];
  bool _chargement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    // Saisis AVANT le premier `await` : après, le contexte peut être démonté.
    final depotListes = context.read<ContactListsRepository>();
    final depotContacts = context.read<ContactsRepository>();
    try {
      // Les deux ensemble : sans le répertoire, le sélecteur de membres serait
      // vide et l'écran de création inutilisable.
      final listes = await depotListes.list();
      final contacts = await depotContacts.list();
      if (!mounted) return;
      // Cet écran est le SEUL endroit où une sonnerie de liste se change : sans
      // cette ligne, la nouvelle sonnerie n'aurait pris effet qu'au prochain
      // passage par l'accueil, et l'utilisateur aurait conclu qu'elle ne marche
      // pas.
      context.read<SonneriesDeListes>().alimenter(listes);
      setState(() {
        _listes = listes;
        _contacts = contacts;
        _chargement = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = tr(context, 'error_with_code', {'code': '${e.statusCode}', 'message': e.message});
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = tr(context, 'lists_load_error');
      });
    }
  }

  /// Ouvre l'éditeur, en création ou en modification.
  Future<void> _editer({ListeContacts? existante}) async {
    final resultat = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditeurListe(
        existante: existante,
        contacts: _contacts,
      ),
    );
    if (resultat == true) _charger();
  }

  Future<void> _supprimer(ListeContacts l) async {
    // Saisi avant la boîte de dialogue, qui est un point d'attente.
    final depot = context.read<ContactListsRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr(context, 'list_delete_q')),
        // Dit ce que ça NE fait PAS : la crainte naturelle est de perdre les
        // contacts eux-mêmes.
        content: Text(
          tr(context, 'list_delete_body', {'nom': l.name}),
        ),
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
    try {
      await depot.supprimer(l.id);
      await _charger();
    } catch (_) {
      showAppSnackBar(tr(context, 'delete_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'contact_lists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.playlist_add),
        label: Text(tr(context, 'list_new')),
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: RefreshIndicator(onRefresh: _charger, child: _corps()),
      ),
    );
  }

  Widget _corps() {
    if (_listes == null && _chargement) {
      return Center(child: CircularProgressIndicator(color: accentOf(context)));
    }
    if (_erreur != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.cloud_off,
                  size: 48, color: faintOf(context, Colors.black26)),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _charger, child: Text(tr(context, 'retry'))),
            ]),
          ),
        ),
      ]);
    }

    final listes = List<ListeContacts>.from(_listes ?? const <ListeContacts>[])
      ..sort((a, b) => comparePourTri(a.name, b.name));

    if (listes.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              Icon(Icons.playlist_add_check,
                  size: 56, color: faintOf(context, Colors.black26)),
              const SizedBox(height: 16),
              Text(
                tr(context, 'lists_empty'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'lists_empty_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedOf(context, Colors.black54)),
              ),
            ]),
          ),
        ),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: listes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _tuile(listes[i]),
    );
  }

  Widget _tuile(ListeContacts l) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final couleur =
        couleurDeListe(l.color, sombre: sombre) ?? accentOf(context);
    final nb = l.members.length;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: couleur,
        child: Text(
          // L'initiale de la liste : un repère visuel qui ne dépend d'aucune
          // ressource à charger.
          l.name.isEmpty ? "?" : l.name.characters.first.toUpperCase(),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        nb == 0
            ? tr(context, 'list_no_members')
            : nb == 1
                ? trN(context, 'list_members', 1, {'noms': l.members.first.displayName})
                : trN(context, 'list_members', nb, {'noms': l.members.take(2).map((m) => m.displayName).join(", ")}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _editer(existante: l),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == "editer") _editer(existante: l);
          if (v == "supprimer") _supprimer(l);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: "editer", child: Text(tr(context, 'edit'))),
          PopupMenuItem(value: "supprimer", child: Text(tr(context, 'delete'))),
        ],
      ),
    );
  }
}

/// Feuille de création / modification d'une liste.
class _EditeurListe extends StatefulWidget {
  const _EditeurListe({required this.existante, required this.contacts});

  final ListeContacts? existante;
  final List<Contact> contacts;

  @override
  State<_EditeurListe> createState() => _EditeurListeState();
}

class _EditeurListeState extends State<_EditeurListe> {
  late final TextEditingController _nomCtrl;
  final _rechercheCtrl = TextEditingController();
  String _recherche = "";
  late Set<String> _choisis;
  bool _envoi = false;

  /// Teinte retenue, parmi les cinq du contrat partagé avec le web.
  late String _teinte;

  /// Sonnerie retenue — l'URL `/api/media/<id>`, ou `null` pour celle par
  /// défaut. C'est la MÊME valeur que le catalogue porte, comparable telle
  /// quelle : ne jamais la transformer avant de l'envoyer.
  String? _sonnerie;

  /// Le catalogue de l'utilisateur, chargé une fois à l'ouverture.
  List<Sonnerie> _catalogue = const [];

  /// Numéros Alanya saisis à la main, à rattacher par le SERVEUR.
  ///
  /// 🐛 **ON NE POUVAIT AJOUTER QUE DES CONTACTS DÉJÀ ENREGISTRÉS** (signalé le
  /// 19/08/2026). Le dépôt acceptait pourtant `memberNumbers` depuis le premier
  /// jour, et le serveur renvoyait déjà `unknownNumbers` — mais l'écran
  /// n'envoyait jamais de numéro, si bien que la branche qui traite les numéros
  /// non rattachés était du code mort. Il manquait la saisie.
  final Set<String> _numeros = {};

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController(text: widget.existante?.name ?? "");
    // Une liste existante garde SA teinte si elle en a une de connue ; une
    // nouvelle prend la première de la palette plutôt que « aucune » — une
    // pastille grise ne se distingue de rien.
    final actuelle = widget.existante?.color;
    _teinte =
        paletteListes.contains(actuelle) ? actuelle! : paletteListes.first;
    _sonnerie = widget.existante?.ringtone;
    _chargerCatalogue();
    // Les membres déjà en place, par identifiant de COMPTE — c'est ce que le
    // serveur attend dans `memberIds`.
    _choisis = {...?widget.existante?.members.map((m) => m.id)};
  }

  /// Charge le catalogue de sonneries, en échec silencieux.
  ///
  /// ⚠️ Un catalogue vide ou inaccessible ne doit PAS empêcher de créer une
  /// liste : le choix de sonnerie disparaît, tout le reste fonctionne.
  Future<void> _chargerCatalogue() async {
    try {
      final c = await context.read<RingtonesRepository>().list();
      if (mounted) setState(() => _catalogue = c);
    } catch (_) {
      if (mounted) setState(() => _catalogue = const []);
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _rechercheCtrl.dispose();
    super.dispose();
  }

  /// Les membres déjà dans la liste qui ne sont PAS dans le répertoire.
  ///
  /// 🐛 **ILS ÉTAIENT INVISIBLES, DONC IMPOSSIBLES À RETIRER.** L'éditeur ne
  /// listait que le carnet d'adresses ; quelqu'un ajouté par son numéro, ou
  /// sorti du répertoire depuis, restait membre sans apparaître nulle part. Le
  /// modèle prévenait pourtant que `isContact` peut être faux — « le client doit
  /// savoir afficher quelqu'un qu'il ne connaît plus ». C'est ici que ça se joue.
  List<MembreDeListe> get _horsRepertoire {
    final membres = widget.existante?.members;
    if (membres == null) return const [];
    final connus = widget.contacts.map((c) => c.userId).toSet();
    return membres.where((m) => !connus.contains(m.id)).toList()
      ..sort((a, b) => comparePourTri(a.displayName, b.displayName));
  }

  /// Ouvre le sélecteur du transfert d'appel — celui qui sait saisir un numéro.
  ///
  /// Réutilisé tel quel plutôt que redéveloppé : c'est déjà le pavé que
  /// l'utilisateur connaît, et en écrire un second aurait fait deux règles de
  /// validation d'Alanya ID à tenir accordées.
  Future<void> _ajouterParNumero() async {
    final dejaLa = <String>[
      ..._numeros,
      ...widget.contacts
          .where((c) => _choisis.contains(c.userId))
          .map((c) => stripAlanyaId(c.publicNumber)),
    ];
    final choisis = await ContactPickerSheet.show(
      context,
      title: tr(context, 'list_add_to'),
      confirmLabel: tr(context, 'add'),
      excludeNumbers: dejaLa,
    );
    if (choisis == null || choisis.isEmpty || !mounted) return;
    setState(() {
      for (final brut in choisis) {
        final propre = stripAlanyaId(brut);
        if (propre.isEmpty) continue;
        // Un numéro qui EST déjà un contact rejoint `_choisis` : le serveur
        // n'aurait pas à le résoudre, et il apparaîtrait alors deux fois —
        // coché dans la liste, et en pastille juste au-dessus.
        Contact? connu;
        for (final c in widget.contacts) {
          if (stripAlanyaId(c.publicNumber) == propre) {
            connu = c;
            break;
          }
        }
        if (connu != null) {
          _choisis.add(connu.userId);
        } else {
          _numeros.add(propre);
        }
      }
    });
  }

  List<Contact> get _visibles {
    final filtres = _recherche.trim().isEmpty
        ? List<Contact>.from(widget.contacts)
        : widget.contacts
            .where((c) =>
                contientRecherche(c.displayName, _recherche) ||
                c.publicNumber.contains(stripAlanyaId(_recherche)))
            .toList();
    filtres.sort((a, b) => comparePourTri(a.displayName, b.displayName));
    return filtres;
  }

  Future<void> _valider() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      showAppSnackBar(tr(context, 'list_name_required'));
      return;
    }
    setState(() => _envoi = true);
    final depot = context.read<ContactListsRepository>();
    try {
      // ⚠️ On envoie TOUJOURS l'ensemble voulu, jamais un delta : la route
      // remplace les membres, elle n'ajoute pas.
      final r = widget.existante == null
          ? await depot.creer(
              nom: nom,
              membreIds: _choisis.toList(),
              numeros: _numeros.toList(),
              couleur: _teinte,
              sonnerie: (url: _sonnerie))
          : await depot.modifier(widget.existante!.id,
              nom: nom,
              membreIds: _choisis.toList(),
              numeros: _numeros.toList(),
              couleur: _teinte,
              sonnerie: (url: _sonnerie));

      if (!mounted) return;
      if (r.numerosInconnus.isNotEmpty) {
        // Dit lesquels n'ont pas été retenus, plutôt que de laisser compter.
        showAppSnackBar(
          tr(context, 'list_unknown_numbers',
              {'numeros': r.numerosInconnus.join(", ")}),
        );
      }
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _envoi = false);
      showAppSnackBar(e.message);
    } catch (_) {
      if (mounted) setState(() => _envoi = false);
      showAppSnackBar(tr(context, 'save_failed_short'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final hors = _horsRepertoire;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controleur) => Container(
        decoration: BoxDecoration(
          color: surfacesOf(context).surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: faintOf(context, Colors.black26),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _nomCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr(context, 'list_name'),
                hintText: tr(context, 'list_name_hint'),
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
          ),
          // --- Teinte de la liste ---
          //
          // Palette FIXE de cinq teintes, celle du web. Un choix libre laisserait
          // prendre une couleur illisible sur l'un des quatre thèmes ; c'est la
          // raison que donne `contact-lists-affichage.ts`, et elle vaut ici.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Row(children: [
              Text(tr(context, 'color'),
                  style: TextStyle(
                      fontSize: 13, color: mutedOf(context, Colors.black54))),
              const SizedBox(width: 14),
              ...paletteListes.map((t) {
                final choisie = t == _teinte;
                final c = couleurDeListe(t,
                        sombre:
                            Theme.of(context).brightness == Brightness.dark) ??
                    accentOf(context);
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Semantics(
                    label: libelleTeinte(t),
                    selected: choisie,
                    child: InkWell(
                      onTap: () => setState(() => _teinte = t),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          // La sélection se marque par un ANNEAU, pas par la
                          // seule teinte : sur cinq pastilles colorées, un
                          // simple changement de nuance ne se voit pas.
                          border: Border.all(
                            color: choisie
                                ? (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: choisie
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                );
              }),
            ]),
          ),
          // --- Sonnerie de la liste ---
          //
          // ⚠️ N'APPARAÎT QUE SI LE CATALOGUE N'EST PAS VIDE. Proposer un choix
          // sans option laisserait croire à une fonctionnalité cassée ; renvoyer
          // vers l'import depuis ici mêlerait deux tâches. Le libellé de l'état
          // vide, lui, dit où aller.
          if (_catalogue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Row(children: [
                Text(tr(context, 'ringtone'),
                    style: TextStyle(
                        fontSize: 13, color: mutedOf(context, Colors.black54))),
                const SizedBox(width: 14),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _catalogue.any((s) => s.url == _sonnerie)
                          ? _sonnerie
                          // Une sonnerie retirée du catalogue depuis : on
                          // retombe sur « par défaut » plutôt que d'afficher un
                          // choix vide, et l'enregistrement la corrigera.
                          : null,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(tr(context, 'default_value')),
                        ),
                        ..._catalogue.map((s) => DropdownMenuItem<String?>(
                              value: s.url,
                              child: Text(s.label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _sonnerie = v),
                    ),
                  ),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextField(
              controller: _rechercheCtrl,
              onChanged: (v) => setState(() => _recherche = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr(context, 'search_contact'),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: surfacesOf(context).surfaceHaute,
              ),
            ),
          ),
          // --- Ajout par numéro ---
          //
          // Le bouton est posé SOUS la recherche et AU-DESSUS de la liste : on
          // cherche d'abord dans son carnet, on saisit un numéro seulement
          // quand la personne n'y est pas.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _ajouterParNumero,
                icon: const Icon(Icons.dialpad, size: 18),
                label: Text(tr(context, 'list_add_by_number')),
              ),
            ),
          ),
          if (_numeros.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _numeros
                      .map((n) => InputChip(
                            label: Text(formatAlanyaId(n),
                                style: alanyaIdStyleOf(context)),
                            avatar: const Icon(Icons.dialpad, size: 16),
                            // Retirable tant que la liste n'est pas enregistrée :
                            // après, la personne devient un membre ordinaire et
                            // se décoche comme les autres.
                            onDeleted: () => setState(() => _numeros.remove(n)),
                          ))
                      .toList(),
                ),
              ),
            ),
          // Le compteur est affiché en permanence : sur une longue liste, on
          // perd sinon le fil de ce qu'on a coché.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                // Les numéros saisis comptent : ils seront membres eux aussi.
                // Les omettre ferait lire « 2 membres » sur une liste qui va en
                // compter quatre.
                (() {
                  final n = _choisis.length + _numeros.length;
                  if (n == 0) return tr(context, 'list_none_selected');
                  return trN(context, 'list_selected', n);
                })(),
                style: TextStyle(
                    fontSize: 12.5, color: mutedOf(context, Colors.black54)),
              ),
            ),
          ),
          Expanded(
            child: visibles.isEmpty && hors.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.contacts.isEmpty
                            ? tr(context, 'book_empty')
                            : tr(context, 'no_contact_matches', {'q': _recherche.trim()}),
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: mutedOf(context, Colors.black54)),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: controleur,
                    // Les membres hors répertoire PASSENT DEVANT : ils ne sont
                    // trouvables par aucune recherche du carnet, et c'est
                    // justement eux qu'on vient retirer.
                    itemCount: hors.length + visibles.length,
                    itemBuilder: (_, i) {
                      if (i < hors.length) {
                        final m = hors[i];
                        return CheckboxListTile(
                          value: _choisis.contains(m.id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _choisis.add(m.id);
                            } else {
                              _choisis.remove(m.id);
                            }
                          }),
                          title: Text(m.displayName),
                          subtitle: Text(
                            tr(context, 'out_of_book', {'id': formatAlanyaId(m.publicNumber)}),
                            style: alanyaIdStyleOf(context),
                          ),
                        );
                      }
                      final c = visibles[i - hors.length];
                      return CheckboxListTile(
                        value: _choisis.contains(c.userId),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _choisis.add(c.userId);
                          } else {
                            _choisis.remove(c.userId);
                          }
                        }),
                        title: Text(c.displayName),
                        subtitle: Text(formatAlanyaId(c.publicNumber),
                            style: alanyaIdStyleOf(context)),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _envoi ? null : _valider,
                  icon: _envoi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(_envoi
                      ? tr(context, 'saving')
                      : widget.existante == null
                          ? tr(context, 'list_create')
                          : tr(context, 'save')),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
