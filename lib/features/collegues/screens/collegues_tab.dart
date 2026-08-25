import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../collegues_repository.dart';
import '../widgets/tuile_collegue.dart';
import 'service_membres_screen.dart';

/// Onglet **Collègues** : les services de mon entreprise, et qui les tient.
///
/// Deux niveaux, plus un raccourci :
///   1. la liste des services, avec leur effectif ;
///   2. les collègues d'un service (écran suivant) ;
///   +  une RECHERCHE qui traverse les deux.
///
/// 🔴 LA RECHERCHE N'EST PAS UN FILTRE DE CETTE LISTE. Elle interroge le
/// serveur sur TOUS les agents de l'entreprise, services confondus — et c'est
/// indispensable : un agent peut n'être rattaché à AUCUN service (cas réel en
/// production), et la navigation par service ne peut alors pas l'atteindre.
/// Sans elle, un collègue existant serait introuvable dans son propre annuaire.
class ColleguesTab extends StatefulWidget {
  const ColleguesTab({super.key});

  @override
  State<ColleguesTab> createState() => _ColleguesTabState();
}

class _ColleguesTabState extends State<ColleguesTab> {
  final _rechercheCtrl = TextEditingController();
  Timer? _debounce;

  List<ServiceCollegues>? _services;
  bool _erreur = false;

  /// Résultats de la recherche serveur. `null` = on n'est pas en recherche.
  List<Collegue>? _resultats;
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
      final liste = await context.read<ColleguesRepository>().services();
      if (!mounted) return;
      setState(() => _services = liste);
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  /// La recherche part APRÈS une pause de frappe.
  ///
  /// ⚠️ Sans ce délai, chaque caractère déclenche une requête : huit lettres
  /// tapées normalement lancent huit appels dont sept sont périmés à leur
  /// arrivée — et rien ne garantit qu'ils reviennent dans l'ordre, si bien que
  /// l'écran peut finir sur le résultat d'une saisie intermédiaire.
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
      final trouves = await context.read<ColleguesRepository>().chercher(q);
      if (!mounted) return;
      // La saisie a pu changer pendant l'aller-retour : on ne pose le résultat
      // que s'il correspond ENCORE à ce qui est écrit.
      if (_rechercheCtrl.text.trim() != q) return;
      setState(() {
        _resultats = trouves;
        _recherche = false;
      });
    } on ApiException {
      if (mounted) setState(() => _recherche = false);
    } catch (_) {
      if (mounted) setState(() => _recherche = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);

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
                hintText: tr(context, 'colleagues_search_hint'),
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _charger,
              child: _resultats != null || _recherche
                  ? _vueRecherche(muted)
                  : _vueServices(muted),
            ),
          ),
        ],
      ),
    );
  }

  // ── Les services ────────────────────────────────────────────────────────
  Widget _vueServices(Color muted) {
    if (_erreur) {
      return _message(tr(context, 'server_unreachable'), muted, avecReessai: true);
    }
    final services = _services;
    if (services == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (services.isEmpty) {
      return _message(tr(context, 'colleagues_no_service'), muted);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: services.length,
      itemBuilder: (_, i) {
        final s = services[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accentOf(context).withValues(alpha: 0.15),
              child: Icon(Icons.badge_outlined, color: accentOf(context)),
            ),
            title: Text(s.nom,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            // L'effectif est ANNONCÉ, y compris à zéro : un service configuré
            // mais sans personne est une information, pas une ligne à cacher.
            subtitle: Text(
              s.effectif == 0
                  ? tr(context, 'colleagues_count_none')
                  : (s.effectif == 1
                      ? tr(context, 'colleagues_count_one')
                      : tr(context, 'colleagues_count_many')
                          .replaceFirst('{n}', '${s.effectif}')),
              style: TextStyle(color: muted, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ServiceMembresScreen(service: s.nom),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── La recherche ────────────────────────────────────────────────────────
  Widget _vueRecherche(Color muted) {
    if (_recherche) {
      return const Center(child: CircularProgressIndicator());
    }
    final trouves = _resultats ?? const <Collegue>[];
    if (trouves.isEmpty) {
      return _message(tr(context, 'colleagues_no_match'), muted);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: trouves.length,
      itemBuilder: (_, i) => TuileCollegue(collegue: trouves[i]),
    );
  }

  Widget _message(String texte, Color muted, {bool avecReessai = false}) {
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
