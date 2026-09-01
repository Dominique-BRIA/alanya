import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../auth/auth_controller.dart';
import '../entreprises_repository.dart';
import 'fiche_entreprise_screen.dart';

/// Onglet **Entreprises** : l'annuaire des standards qu'on peut appeler.
///
/// Deux niveaux, plus un raccourci :
///   1. les types d'entreprise ;
///   2. les entreprises de ce type ;
///   +  une RECHERCHE.
///
/// 🔴 UN FILTRE PAR PAYS COMMANDE TOUT L'ÉCRAN depuis le 31/08/2026 (demande du
/// user). L'annuaire ne montrait auparavant que le pays du compte, sans moyen
/// d'en changer. Le filtre part sur ce même pays — le comportement d'avant
/// devient donc son cas par défaut — et l'on peut désormais regarder ailleurs.
///
/// 🔴 LA RECHERCHE SUIT LE FILTRE, elle aussi (même demande, formulée juste
/// après : « je pense que c'est mieux si la recherche est alignée sur le
/// filtrage »). Elle ignorait le pays jusque-là, à la demande du user
/// également : **ne pas revenir en arrière sans lui**.
///
/// ⚠️ CE QUE CE CHOIX COÛTE, et pourquoi il tient quand même : la recherche
/// était le seul chemin vers une entreprise dont le pays n'est pas renseigné.
/// Le serveur INCLUT désormais ces entreprises-là dans tous les pays — une
/// entreprise sans pays n'est pas « d'un autre pays », elle est non classée.
/// Sans cette règle, la moitié de l'annuaire de production (1 entreprise sur 2,
/// mesuré le 31/08) serait devenue introuvable.
///
/// Le menu ne propose QUE des pays qui ont au moins une entreprise : c'est le
/// serveur qui le dit, lui seul le sait.
///
/// ⚠️ Aucun emoji ni sticker — règle du projet.
class EntreprisesTab extends StatefulWidget {
  const EntreprisesTab({super.key});

  @override
  State<EntreprisesTab> createState() => _EntreprisesTabState();
}

class _EntreprisesTabState extends State<EntreprisesTab> {
  final _rechercheCtrl = TextEditingController();
  Timer? _debounce;

  List<TypeEntreprise>? _types;
  bool _erreur = false;

  /// Le type ouvert, ou `null` quand on est sur la liste des types.
  TypeEntreprise? _typeOuvert;
  List<Entreprise>? _entreprises;

  /// Résultats de la recherche serveur. `null` = on n'est pas en recherche.
  List<Entreprise>? _resultats;
  bool _recherche = false;

  /// Les pays proposés par le filtre — ceux qui ont au moins une entreprise.
  List<PaysEntreprise> _pays = const [];

  /// Le pays sélectionné, ou `null` tant qu'on n'a rien choisi.
  ///
  /// 🔴 `null` NE VEUT PAS DIRE « TOUS LES PAYS » : il veut dire « le serveur
  /// décide », et le serveur retombe alors sur le pays du compte. C'est ce qui
  /// donne au filtre sa valeur par défaut sans que le client ait à connaître le
  /// pays de l'utilisateur ni à l'annoncer.
  int? _paysChoisi;

  @override
  void initState() {
    super.initState();
    _charger();
    _chargerPays();
  }

  /// Charge la liste du filtre, et y repère le pays de l'utilisateur.
  ///
  /// ⚠️ ÉCHEC SILENCIEUX : sans la liste, le filtre ne s'affiche pas et
  /// l'annuaire se comporte comme avant. Une erreur en travers de l'écran pour
  /// un menu qui n'est pas la fonction principale serait disproportionnée.
  Future<void> _chargerPays() async {
    try {
      final liste = await context.read<EntreprisesRepository>().paysDisponibles();
      if (!mounted) return;
      final mien = context.read<AuthController>().user?.idPays;
      setState(() {
        _pays = liste;
        // Le pays du compte devient la sélection affichée — mais seulement
        // s'il est dans la liste : le montrer alors qu'il n'a aucune entreprise
        // afficherait un menu pointant sur une liste vide.
        if (_paysChoisi == null &&
            mien != null &&
            liste.any((p) => p.idPays == mien)) {
          _paysChoisi = mien;
        }
      });
    } catch (_) {
      // Filtre indisponible : l'annuaire reste utilisable tel quel.
    }
  }

  /// Rejoue ce qui est à l'écran avec le pays courant.
  ///
  /// Les trois vues en dépendent : les types, les entreprises d'un type ouvert,
  /// et la recherche en cours. N'en rafraîchir qu'une laisserait les autres
  /// afficher le pays précédent sans que rien ne le dise.
  Future<void> _appliquePays(int? idPays) async {
    setState(() {
      _paysChoisi = idPays;
      _types = null;
      _entreprises = null;
    });
    await _charger();
    final ouvert = _typeOuvert;
    if (ouvert != null) await _ouvrirType(ouvert);
    final q = _rechercheCtrl.text.trim();
    if (q.isNotEmpty) await _chercher(q);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _erreur = false);
    try {
      final liste = await context.read<EntreprisesRepository>().types(idPays: _paysChoisi);
      if (!mounted) return;
      setState(() => _types = liste);
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  Future<void> _ouvrirType(TypeEntreprise t) async {
    setState(() {
      _typeOuvert = t;
      _entreprises = null;
    });
    try {
      final liste = await context.read<EntreprisesRepository>().duType(t.id, idPays: _paysChoisi);
      if (!mounted) return;
      setState(() => _entreprises = liste);
    } catch (_) {
      if (mounted) setState(() => _entreprises = const []);
    }
  }

  /// La recherche part APRÈS une pause de frappe.
  ///
  /// ⚠️ Sans ce délai, chaque caractère déclenche une requête : huit lettres
  /// tapées normalement lancent huit appels dont sept sont périmés à leur
  /// arrivée — et rien ne garantit qu'ils reviennent dans l'ordre.
  void _surSaisie(String valeur) {
    _debounce?.cancel();
    final q = valeur.trim();
    if (q.isEmpty) {
      setState(() {
        _resultats = null;
        _recherche = false;
      });
      return;
    }
    setState(() => _recherche = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _chercher(q));
  }

  Future<void> _chercher(String q) async {
    try {
      final trouves = await context.read<EntreprisesRepository>().chercher(q, idPays: _paysChoisi);
      if (!mounted) return;
      // La saisie a pu changer pendant l'aller-retour : on ne pose le résultat
      // que s'il correspond ENCORE à ce qui est écrit.
      if (_rechercheCtrl.text.trim() != q) return;
      setState(() {
        _resultats = trouves;
        _recherche = false;
      });
    } catch (_) {
      if (mounted) setState(() => _recherche = false);
    }
  }

  /// LE FILTRE PAR PAYS, à droite de la barre de recherche.
  ///
  /// Un bouton et non un menu déroulant étalé : la liste peut compter des
  /// dizaines de pays, et un `DropdownButton` de cette taille écraserait la
  /// barre de recherche à côté de laquelle il vit.
  ///
  /// ⚠️ RIEN NE S'AFFICHE TANT QUE LA LISTE EST VIDE — serveur plus ancien qui
  /// ne connaît pas la route, ou aucune entreprise nulle part. Un filtre qui
  /// n'offre aucun choix n'est pas un filtre, c'est une impasse.
  Widget _filtrePays() {
    if (_pays.isEmpty) return const SizedBox.shrink();
    final choisi = _pays.where((p) => p.idPays == _paysChoisi).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PopupMenuButton<int>(
        tooltip: "Filtrer par pays",
        onSelected: _appliquePays,
        itemBuilder: (_) => [
          for (final p in _pays)
            PopupMenuItem<int>(
              value: p.idPays,
              child: Row(children: [
                Icon(
                  p.idPays == _paysChoisi
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: accentOf(context),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(p.libelle, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: mutedOf(context, Colors.black26)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.public, size: 18, color: accentOf(context)),
            const SizedBox(width: 6),
            // Le nom du pays, borné : « République démocratique du Congo » ne
            // doit pas repousser la barre de recherche hors de l'écran.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                choisi?.libelle ?? "Pays",
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ]),
        ),
      ),
    );
  }

  void _ouvrirFiche(Entreprise e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FicheEntrepriseScreen(idEntreprise: e.id, titre: e.libelle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final enRecherche = _resultats != null || _recherche;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _rechercheCtrl,
                  onChanged: _surSaisie,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr(context, 'company_search_hint'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _rechercheCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _rechercheCtrl.clear();
                              _surSaisie("");
                            },
                          ),
                  ),
                ),
              ),
              _filtrePays(),
            ]),
          ),

          // Fil d'Ariane du second niveau. Masqué en recherche : celle-ci
          // traverse les types, on n'est plus « dans » l'un d'eux.
          if (_typeOuvert != null && !enRecherche)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _typeOuvert = null;
                  _entreprises = null;
                }),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(_typeOuvert!.libelle),
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _charger,
              child: enRecherche
                  ? _vueEntreprises(
                      _recherche ? null : _resultats,
                      tr(context, 'company_no_match'),
                      muted,
                    )
                  : _typeOuvert != null
                      ? _vueEntreprises(
                          _entreprises,
                          tr(context, 'company_none_here'),
                          muted,
                        )
                      : _vueTypes(muted),
            ),
          ),
        ],
      ),
    );
  }

  // ── Les types ───────────────────────────────────────────────────────────
  Widget _vueTypes(Color muted) {
    if (_erreur) return _message(tr(context, 'server_unreachable'), muted, true);
    final types = _types;
    if (types == null) return const Center(child: CircularProgressIndicator());
    if (types.isEmpty) return _message(tr(context, 'company_no_type'), muted, false);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: types.length,
      itemBuilder: (_, i) {
        final t = types[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accentOf(context).withValues(alpha: 0.15),
              child: Icon(Icons.domain_outlined, color: accentOf(context)),
            ),
            title: Text(t.libelle,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            /*
             * L'effectif est ANNONCÉ, y compris à zéro — le serveur le calcule
             * APRÈS le filtre par pays. Zéro ne veut pas dire « ce type n'existe
             * pas » mais « aucune dans ton pays », et le sous-titre le dit :
             * l'utilisateur sait alors que la recherche peut encore trouver.
             */
            subtitle: Text(
              t.nbEntreprises == 0
                  ? tr(context, 'company_count_none')
                  : (t.nbEntreprises == 1
                      ? tr(context, 'company_count_one')
                      : tr(context, 'company_count_many')
                          .replaceFirst('{n}', '${t.nbEntreprises}')),
              style: TextStyle(color: muted, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrirType(t),
          ),
        );
      },
    );
  }

  // ── Les entreprises ─────────────────────────────────────────────────────
  Widget _vueEntreprises(List<Entreprise>? liste, String messageVide, Color muted) {
    if (liste == null) return const Center(child: CircularProgressIndicator());
    if (liste.isEmpty) return _message(messageVide, muted, false);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: liste.length,
      itemBuilder: (_, i) {
        final e = liste[i];
        // En recherche, le pays est montré : il n'est plus garanti d'être le
        // sien, et c'est précisément ce que la recherche permet de trouver.
        final sousTitre = [e.ville, e.pays].whereType<String>().join(", ");
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accentOf(context).withValues(alpha: 0.15),
              child: Icon(Icons.business_outlined, color: accentOf(context)),
            ),
            title: Text(e.libelle,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: sousTitre.isEmpty
                ? null
                : Text(sousTitre,
                    style: TextStyle(color: muted, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _ouvrirFiche(e),
          ),
        );
      },
    );
  }

  Widget _message(String texte, Color muted, bool avecReessai) {
    // `ListView` et non `Center` : le message doit rester tirable pour
    // rafraîchir, sinon un écran d'erreur devient un cul-de-sac.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(texte,
              textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ),
        if (avecReessai) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
                onPressed: _charger, child: Text(tr(context, 'retry'))),
          ),
        ],
      ],
    );
  }
}
