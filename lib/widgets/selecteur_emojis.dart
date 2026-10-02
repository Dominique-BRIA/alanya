import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/emojis_catalogue.dart';
import '../l10n/app_localizations.dart';
import '../theme/alanya_theme.dart';

/// SÉLECTEUR D'EMOJIS — le même catalogue que le web (1 812 emojis, 8
/// catégories), plus les récents et une recherche.
///
/// Le chat n'en proposait que 24, et le web aucun (signalé le 02/10/2026). Le
/// catalogue est GÉNÉRÉ (`lib/core/emojis_catalogue.dart`, par
/// `STAGE-WEB/scripts/generer-emojis.mjs`) : les deux clients montrent les
/// mêmes emojis, dans le même ordre, sous les mêmes catégories.
///
/// ⚠️ UNE CATÉGORIE À LA FOIS, choisie par les onglets. Un défilement continu
/// sur 1 800 emojis obligerait à construire les sections lointaines pour y
/// sauter ; une grille par catégorie reste paresseuse (`GridView.builder`).
///
/// ⚠️ [sombre] force la palette sombre : la feuille des statuts s'ouvre
/// par-dessus un éditeur noir, quel que soit le thème de l'application.
class SelecteurEmojis extends StatefulWidget {
  const SelecteurEmojis({
    super.key,
    required this.onChoisir,
    this.sombre = false,
  });

  final ValueChanged<String> onChoisir;
  final bool sombre;

  @override
  State<SelecteurEmojis> createState() => _SelecteurEmojisState();
}

const _cleRecents = 'emojis_recents';
const _maxRecents = 32;
const _recents = 'recents';

/// Même normalisation que les mots-clés générés : sans accents, minuscules.
///
/// ⚠️ « œ » et « æ » deviennent DEUX lettres : « cœur » doit trouver « coeur ».
String _nu(String texte) {
  const avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const sans = 'aaaaaaceeeeiiiinooooouuuuyy';
  final sortie = StringBuffer();
  for (final c in texte.toLowerCase().trim().split('')) {
    if (c == 'œ') {
      sortie.write('oe');
    } else if (c == 'æ') {
      sortie.write('ae');
    } else {
      final i = avec.indexOf(c);
      sortie.write(i < 0 ? c : sans[i]);
    }
  }
  return sortie.toString();
}

const Map<String, IconData> _icones = {
  _recents: Icons.access_time,
  'smileys': Icons.emoji_emotions_outlined,
  'nature': Icons.eco_outlined,
  'nourriture': Icons.restaurant_outlined,
  'activites': Icons.sports_soccer_outlined,
  'voyages': Icons.directions_car_outlined,
  'objets': Icons.lightbulb_outline,
  'symboles': Icons.favorite_border,
  'drapeaux': Icons.flag_outlined,
};

class _SelecteurEmojisState extends State<SelecteurEmojis> {
  final _rechercheCtrl = TextEditingController();
  List<String> _recentsListe = const [];
  String? _actif;
  String _requete = '';

  @override
  void initState() {
    super.initState();
    _chargerRecents();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liste = prefs.getStringList(_cleRecents) ?? const [];
      if (!mounted) return;
      setState(() {
        _recentsListe = liste;
        _actif ??= liste.isNotEmpty ? _recents : catalogueEmojis.first.id;
      });
    } catch (_) {
      // Les récents sont un confort : sans eux, on ouvre sur les smileys.
      if (mounted) setState(() => _actif ??= catalogueEmojis.first.id);
    }
  }

  Future<void> _choisir(String emoji) async {
    widget.onChoisir(emoji);
    final liste = [emoji, ..._recentsListe.where((e) => e != emoji)]
        .take(_maxRecents)
        .toList();
    setState(() => _recentsListe = liste);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cleRecents, liste);
    } catch (_) {
      // Non retenu : rien de plus grave qu'un récent qui manque.
    }
  }

  List<String> get _visibles {
    final q = _nu(_requete);
    if (q.isNotEmpty) {
      final mots = q.split(RegExp(r'\s+'));
      return [
        for (final c in catalogueEmojis)
          for (final (emoji, cles) in c.emojis)
            if (mots.every(cles.contains)) emoji,
      ];
    }
    final actif = _actif ?? catalogueEmojis.first.id;
    if (actif == _recents) return _recentsListe;
    return catalogueEmojis
        .firstWhere((c) => c.id == actif)
        .emojis
        .map((e) => e.$1)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.sombre ? AlanyaColors.terracottaNuit : accentOf(context);
    final muted = widget.sombre ? Colors.white60 : mutedOf(context, Colors.black54);
    final texte = widget.sombre ? Colors.white : null;
    final enRecherche = _requete.trim().isNotEmpty;
    final onglets = [
      if (_recentsListe.isNotEmpty) _recents,
      for (final c in catalogueEmojis) c.id,
    ];
    final visibles = _visibles;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            controller: _rechercheCtrl,
            onChanged: (v) => setState(() => _requete = v),
            style: TextStyle(color: texte, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: tr(context, 'emoji_search_hint'),
              hintStyle: TextStyle(color: muted),
              prefixIcon: Icon(Icons.search, size: 20, color: muted),
              suffixIcon: _requete.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: muted),
                      onPressed: () => setState(() {
                        _rechercheCtrl.clear();
                        _requete = '';
                      }),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              for (final id in onglets)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      _actif = id;
                      _rechercheCtrl.clear();
                      _requete = '';
                    }),
                    child: Tooltip(
                      message: tr(context,
                          id == _recents ? 'emoji_recent' : 'emoji_cat_$id'),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: !enRecherche && _actif == id
                                  ? accent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _icones[id],
                          size: 20,
                          color: !enRecherche && _actif == id ? accent : muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: visibles.isEmpty
              ? Center(
                  child: Text(
                    tr(context, enRecherche ? 'emoji_none' : 'emoji_recent'),
                    style: TextStyle(color: muted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 46,
                  ),
                  itemCount: visibles.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _choisir(visibles[i]),
                    child: Center(
                      child: Text(visibles[i],
                          style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
