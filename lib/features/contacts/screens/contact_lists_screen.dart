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
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/contact_picker_sheet.dart';
import '../../../widgets/motif_background.dart';
import '../contact_lists_repository.dart';
import '../contacts_repository.dart';
import '../teintes_listes.dart';
import 'sonneries_liste_screen.dart';

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
        toutesLesListes: _listes ?? const [],
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

    /*
     * DES CARTES DÉTACHÉES, ET NON UN TABLEAU DE LIGNES SÉPARÉES PAR UN TRAIT.
     *
     * Une liste de contacts est un OBJET qu'on ouvre, qu'on colore et qu'on
     * renomme — pas une ligne dans un inventaire. La carte le dit : chacune a
     * son bord, son ombre et sa couleur, et l'on comprend au premier regard
     * qu'il y en a quatre distinctes plutôt qu'un bloc de quatre lignes.
     *
     * Le trait de séparation faisait l'inverse : il liait les quatre en un seul
     * pavé, où seule l'initiale changeait.
     */
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        ...listes.map(_tuile),
        // L'AIDE VIENT APRÈS LA LISTE, jamais avant : elle répond à une question
        // qu'on ne se pose qu'après avoir vu les listes — « pourquoi ne puis-je
        // pas ajouter n'importe qui ? ». Placée en tête, elle retarderait
        // l'essentiel pour tout le monde, à chaque ouverture.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
          child: Text(
            tr(context, 'list_help'),
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: mutedOf(context, Colors.black54),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tuile(ListeContacts l) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final couleur =
        couleurDeListe(l.color, sombre: sombre) ?? accentOf(context);
    final nb = l.members.length;
    return Card(
      // Posée à plat, bordée : l'ombre portée d'un `Card` par défaut se perd sur
      // le motif de fond, alors qu'un liseré tient sur les quatre thèmes.
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      color: surfacesOf(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: faintOf(context, Colors.black12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        /*
         * UNE PUCE CARRÉE, ET NON UN CERCLE PORTANT L'INITIALE.
         *
         * Le cercle à initiale est le code visuel d'une PERSONNE — c'est
         * exactement ce que `AvatarCircle` dessine pour un contact, deux écrans
         * plus loin. L'employer pour une liste faisait passer « Famille » pour
         * quelqu'un qui s'appellerait F.
         *
         * Le carré arrondi dit « contenant ». L'icône de dossier le confirme, et
         * la couleur reste le repère qui distingue les quatre d'un coup d'œil —
         * c'est elle que l'utilisateur a choisie, et elle sert déjà à teinter
         * les conversations filtrées.
         */
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: couleur,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.folder_rounded, color: Colors.white, size: 24),
        ),
        title: Text(l.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            nb == 0
                ? tr(context, 'list_no_members')
                : nb == 1
                    ? trN(context, 'list_members', 1,
                        {'noms': l.members.first.displayName})
                    : trN(context, 'list_members', nb, {
                        'noms': l.members
                            .take(2)
                            .map((m) => m.displayName)
                            .join(", ")
                      }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5, color: mutedOf(context, Colors.black54)),
          ),
        ),
        onTap: () => _editer(existante: l),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: mutedOf(context, Colors.black54)),
          onSelected: (v) {
            if (v == "editer") _editer(existante: l);
            if (v == "supprimer") _supprimer(l);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: "editer", child: Text(tr(context, 'edit'))),
            // Les quatre listes d'origine ne se suppriment pas. Le serveur refuse
            // de toute façon (409 `LISTE_PAR_DEFAUT`) : cacher l'entrée évite
            // d'offrir un geste qui ne finirait qu'en message d'erreur.
            //
            // ⚠️ SEULE LA SUPPRESSION EST MASQUÉE. « Modifier » reste offert :
            // ces listes se renomment, se recolorent et changent de sonnerie
            // comme les autres — c'est la clé, pas le nom, qui les identifie.
            if (!l.estParDefaut)
              PopupMenuItem(
                  value: "supprimer", child: Text(tr(context, 'delete'))),
          ],
        ),
      ),
    );
  }
}

/// Feuille de création / modification d'une liste.
class _EditeurListe extends StatefulWidget {
  const _EditeurListe({
    required this.existante,
    required this.contacts,
    required this.toutesLesListes,
  });

  final ListeContacts? existante;
  final List<Contact> contacts;

  /// Toutes les listes du compte, dans l ordre rendu par le serveur.
  ///
  /// ⚠️ Sert a l ecran des sonneries, qui porte l ordre de priorite : le
  /// serveur refuse un reordonnancement qui ne les cite pas TOUTES.
  final List<ListeContacts> toutesLesListes;

  @override
  State<_EditeurListe> createState() => _EditeurListeState();
}

class _EditeurListeState extends State<_EditeurListe> {
  late final TextEditingController _nomCtrl;
  // La recherche a suivi le carnet dans `_SelecteurMembres` : cette feuille-ci
  // ne cherche plus rien, elle ne fait que montrer combien sont choisis.
  late Set<String> _choisis;
  bool _envoi = false;

  /// Teinte retenue, parmi les cinq du contrat partagé avec le web.
  late String _teinte;

  /// Sonnerie retenue — soit l'URL `/api/media/<id>` d'une sonnerie importée,
  /// soit le NOM d'un fichier livré (« liste-bureau.mp3 »). C'est la MÊME valeur
  /// que la base porte, comparable telle quelle : ne jamais la transformer avant
  /// de l'envoyer.
  String? _sonnerie;

  // Le choix de la sonnerie a déménagé dans `SonneriesListeScreen`, avec le
  // catalogue et le repli « par défaut » qui l'accompagnaient. `_sonnerie` reste
  // ici pour une seule raison, et elle est essentielle :
  //
  // ⚠️ IL PRÉSERVE LA SONNERIE À L'ENREGISTREMENT. Le PATCH envoie
  // `sonnerie: (url: _sonnerie)` ; si l'on oubliait ce champ, renommer une liste
  // ou changer sa couleur EFFACERAIT son son au passage.

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
    /*
     * ⚠️ UNE LISTE EXISTANTE GARDE SA TEINTE, même absente de la palette.
     *
     * La palette est passée de cinq NOMS à vingt hexadécimaux. Le test
     * d'appartenance seul aurait donc rejeté « amber » — porté par toutes les
     * listes créées avant — et l'aurait remplacée par le premier rouge de la
     * nouvelle palette. Ouvrir une liste pour renommer en aurait CHANGÉ LA
     * COULEUR, sans que rien ne le dise.
     *
     * On ne retombe sur la première teinte que pour une liste NEUVE : une
     * pastille grise ne se distingue de rien.
     */
    _teinte = (actuelle != null && actuelle.trim().isNotEmpty)
        ? actuelle
        : paletteListes.first;
    _sonnerie = widget.existante?.ringtone;
    // Les membres déjà en place, par identifiant de COMPTE — c'est ce que le
    // serveur attend dans `memberIds`.
    _choisis = {...?widget.existante?.members.map((m) => m.id)};
  }

  // Le catalogue de sonneries n'est plus chargé ici : il a suivi le choix du son
  // dans `SonneriesListeScreen`. Une requête de moins à chaque ouverture de
  // l'éditeur, pour une donnée qu'il n'affichait plus.

  @override
  void dispose() {
    _nomCtrl.dispose();
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

  /// Une ligne cliquable : icône, libellé, valeur à droite, chevron.
  ///
  /// C'est la forme que prennent désormais les réglages d'une liste — ce que
  /// l'on choisit AILLEURS que sur cette feuille. Elle annonce trois choses à la
  /// fois : ce que c'est, ce qui est actuellement choisi, et qu'un appui ouvre
  /// autre chose. Un menu déroulant posé à plat ne disait que la première.
  Widget _ligneAction({
    required IconData icone,
    required String libelle,
    required String valeur,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: surfacesOf(context).surfaceHaute,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Icon(icone, size: 22, color: accentOf(context)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(libelle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ),
              // La valeur s'efface devant le libellé : elle se lit au besoin,
              // elle n'attire pas l'œil comme une action.
              Flexible(
                child: Text(
                  valeur,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5, color: mutedOf(context, Colors.black54)),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 20, color: faintOf(context, Colors.black38)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Ouvre « Sonneries — <liste> ».
  ///
  /// ⚠️ ON PASSE TOUTES LES LISTES, pas seulement celle-ci : l'écran porte aussi
  /// l'ordre de priorité, qui les concerne toutes — et le serveur refuse un
  /// réordonnancement qui ne les cite pas toutes (422 `ORDRE_INCOMPLET`).
  ///
  /// ⚠️ ON FERME L'ÉDITEUR EN REVENANT (`pop(true)`), plutôt que de rester
  /// dessus : les sons viennent d'être écrits en base, et l'éditeur affiche
  /// encore l'état d'avant. Le laisser ouvert offrirait un « Enregistrer » qui
  /// réécrirait des valeurs périmées par-dessus les nouvelles.
  Future<void> _ouvrirSonneries() async {
    final liste = widget.existante;
    if (liste == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SonneriesListeScreen(
          liste: liste,
          toutesLesListes: widget.toutesLesListes,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Ouvre le carnet, et ne retient que ce qui en revient.
  ///
  /// ⚠️ `null` SIGNIFIE « ANNULÉ », et ce n'est pas la même chose qu'une
  /// sélection vide : fermer la feuille d'un balayage doit laisser les membres
  /// tels qu'ils étaient, alors que tout décocher puis enregistrer doit bien
  /// vider la liste. Confondre les deux ferait perdre une sélection au moindre
  /// geste de sortie.
  Future<void> _ouvrirSelecteurMembres() async {
    final resultat = await showModalBottomSheet<_ChoixMembres>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelecteurMembres(
        contacts: widget.contacts,
        horsRepertoire: _horsRepertoire,
        choisisInitiaux: Set<String>.from(_choisis),
        numerosInitiaux: List<String>.from(_numeros),
      ),
    );
    if (resultat == null || !mounted) return;
    setState(() {
      _choisis
        ..clear()
        ..addAll(resultat.choisis);
      _numeros
        ..clear()
        ..addAll(resultat.numeros);
    });
  }

  @override
  Widget build(BuildContext context) {
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
              // ⚠️ LE NOM D'UNE LISTE D'ORIGINE S'ÉDITE, lui aussi. Verrouiller
              // ce champ pour les quatre listes semées serait inventer une
              // règle que le serveur n'applique pas : il n'y refuse QUE la
              // suppression. Et c'est `cle`, pas le nom, qui les identifie —
              // renommer « Bureau » en « Travail » ne casse rien.
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
          // Palette FIXE, celle du web — vingt teintes depuis que cinq ne
          // suffisaient plus. Un choix libre laisserait prendre une couleur
          // illisible sur l'un des quatre thèmes ; c'est la raison que donne
          // `contact-lists-affichage.ts`, et elle vaut ici.
          //
          // ⚠️ `Wrap` et non `Row` : vingt pastilles de 30 px plus leurs marges
          // font 800 px, soit le double d'un écran de téléphone. Une rangée les
          // aurait fait déborder — et Flutter signale un débordement par une
          // bande rayée, pas en repliant.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 0,
                runSpacing: 10,
                children: [
              Text(tr(context, 'list_color_chip'),
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
          // --- Les sons de la liste ---
          //
          // 🔴 ILS NE SE REGLENT PLUS ICI, et la maquette le dit : la feuille de
          // creation ne porte que le nom, la couleur et les membres.
          //
          // La raison est concrete : une liste qui n existe pas encore n a pas
          // d identifiant, et l ecran des sonneries en a besoin — pour
          // enregistrer, et pour afficher l ordre de priorite de TOUTES les
          // listes, dont celle-ci ne fait pas encore partie. On cree d abord, on
          // ecoute ensuite.
          if (widget.existante != null)
            _ligneAction(
              icone: Icons.notifications_none,
              libelle: tr(context, 'ringtones'),
              // La valeur n'est pas répétée ici : les DEUX sons y sont réglés,
              // et n'en montrer qu'un laisserait croire qu'il n'y en a qu'un.
              valeur: "",
              onTap: _ouvrirSonneries,
            ),
          /*
           * LES MEMBRES PASSENT DANS UNE FEUILLE À EUX.
           *
           * 🔴 CE N'EST PAS UN CHOIX D'ESTHÉTIQUE. Tout vivait ici : le nom, la
           * couleur, la sonnerie, la recherche, l'ajout par numéro, le compteur
           * et le carnet entier à cocher. La feuille occupait 85 % de l'écran, et
           * le carnet — la partie la plus haute — poussait le bouton « Créer »
           * hors de vue. Sur un carnet fourni, on ne savait plus si l'on était
           * en train de créer une liste ou de parcourir ses contacts.
           *
           * Une ligne, un chevron, un compte : on voit d'un coup d'œil ce qui est
           * choisi, et l'on n'ouvre le carnet que si l'on veut y toucher. La
           * création tient alors dans un écran qu'on lit sans faire défiler.
           *
           * ⚠️ LA SÉLECTION RESTE PORTÉE PAR CETTE FEUILLE-CI. La sous-feuille ne
           * garde rien : elle reçoit ce qui est coché, rend ce qui l'est à sa
           * fermeture, et l'on ne valide toujours qu'une seule fois, en bas.
           * Deux états de sélection auraient fini par diverger.
           */
          _ligneAction(
            icone: Icons.person_add_alt_1_outlined,
            libelle: tr(context, 'list_add_members'),
            valeur: (() {
              final n = _choisis.length + _numeros.length;
              return n == 0
                  ? tr(context, 'list_no_members')
                  : trN(context, 'list_selected', n);
            })(),
            onTap: _ouvrirSelecteurMembres,
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

/// Ce que la feuille de sélection rapporte : les contacts cochés, et les
/// numéros saisis pour des gens qui ne sont pas au carnet.
///
/// Une classe plutôt qu'un couple anonyme : ces deux ensembles ne se confondent
/// pas — l'un porte des identifiants de compte, l'autre des numéros — et les
/// intervertir à l'appel serait resté silencieux.
class _ChoixMembres {
  const _ChoixMembres(this.choisis, this.numeros);
  final Set<String> choisis;
  final List<String> numeros;
}

/// LE CARNET, dans sa propre feuille.
///
/// Il sortait de l'éditeur de liste, où il occupait toute la hauteur et
/// repoussait le bouton de validation hors de l'écran. Ici il a la place qu'il
/// réclame, et un seul travail : choisir qui entre dans la liste.
///
/// ⚠️ IL NE GARDE RIEN. Il reçoit la sélection en cours, travaille sur une
/// copie, et la rend à sa fermeture. L'éditeur reste seul dépositaire de ce qui
/// sera enregistré — deux états de sélection auraient fini par diverger, et
/// c'est un défaut que ce dépôt a déjà payé sur les listes de l'accueil.
class _SelecteurMembres extends StatefulWidget {
  const _SelecteurMembres({
    required this.contacts,
    required this.horsRepertoire,
    required this.choisisInitiaux,
    required this.numerosInitiaux,
  });

  final List<Contact> contacts;
  final List<MembreDeListe> horsRepertoire;
  final Set<String> choisisInitiaux;
  final List<String> numerosInitiaux;

  @override
  State<_SelecteurMembres> createState() => _SelecteurMembresState();
}

class _SelecteurMembresState extends State<_SelecteurMembres> {
  late final Set<String> _choisis = Set<String>.from(widget.choisisInitiaux);
  late final List<String> _numeros = List<String>.from(widget.numerosInitiaux);
  final _rechercheCtrl = TextEditingController();
  String _recherche = "";

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
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

  /// Le sélecteur du transfert d'appel — celui qui sait saisir un numéro.
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
        // n'aurait sinon aucun moyen de savoir qu'il s'agit de la même personne.
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

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final hors = widget.horsRepertoire;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr(context, 'list_add_members'),
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _rechercheCtrl,
              onChanged: (v) => setState(() => _recherche = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr(context, 'search_contact'),
                prefixIcon: const Icon(Icons.search, size: 20),
                // La croix n'apparaît qu'une fois qu'il y a quelque chose à
                // effacer : offerte à vide, elle ne fait rien et prend la place.
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
              ),
            ),
          ),
          // Le bouton est posé SOUS la recherche et AU-DESSUS de la liste : on
          // cherche d'abord dans son carnet, on saisit un numéro seulement
          // quand la personne n'y est pas.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
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
          Expanded(
            child: visibles.isEmpty && hors.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.contacts.isEmpty
                            ? tr(context, 'book_empty')
                            : tr(context, 'no_contact_matches',
                                {'q': _recherche.trim()}),
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
                            tr(context, 'out_of_book',
                                {'id': formatAlanyaId(m.publicNumber)}),
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
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context)
                      .pop(_ChoixMembres(_choisis, _numeros)),
                  child: Text(tr(context, 'save')),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
