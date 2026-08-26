import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../entreprises_repository.dart';
import 'fiche_entreprise_screen.dart';

/// Onglet **Entreprises** : l'annuaire des standards qu'on peut appeler.
///
/// Deux niveaux, plus un raccourci :
///   1. les types d'entreprise ;
///   2. les entreprises de ce type, DANS MON PAYS ;
///   +  une RECHERCHE qui ignore le pays.
///
/// 🔴 LA RECHERCHE IGNORE LE FILTRE PAR PAYS, et c'est voulu. Naviguer, c'est
/// découvrir ce qu'on peut joindre autour de soi ; chercher, c'est déjà savoir
/// ce qu'on veut. C'est aussi le SEUL chemin vers une entreprise dont le pays
/// n'est pas renseigné — cas réel en production, où « Open solution » n'a pas
/// de pays et n'apparaît donc dans aucune liste filtrée.
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

  @override
  void initState() {
    super.initState();
    _charger();
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
      final liste = await context.read<EntreprisesRepository>().types();
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
      final liste = await context.read<EntreprisesRepository>().duType(t.id);
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
      final trouves = await context.read<EntreprisesRepository>().chercher(q);
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
