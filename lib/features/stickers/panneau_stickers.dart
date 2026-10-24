import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/locale_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/alanya_theme.dart';
import 'boutique_stickers_screen.dart';
import 'image_sticker.dart';
import 'stickers_service.dart';

/// L'ONGLET STICKERS du sélecteur, comme celui de WhatsApp :
///
/// * en haut, une rangée d'icônes — rechercher, récents, favoris, puis un
///   onglet par pack de MON panneau, et « + » (la boutique) au bout ;
/// * dessous, la grille du choix courant ; un toucher ENVOIE le sticker
///   tout de suite, un appui long l'ajoute aux favoris (ou l'en retire).
class PanneauStickers extends StatefulWidget {
  const PanneauStickers({super.key, required this.onEnvoyer, this.sombre = false});

  final ValueChanged<Sticker> onEnvoyer;
  final bool sombre;

  @override
  State<PanneauStickers> createState() => _PanneauStickersState();
}

/// Les onglets fixes ; un pack est désigné par son identifiant (positif).
const _recherche = -1;
const _recents = -2;
const _favoris = -3;

class _PanneauStickersState extends State<PanneauStickers> {
  int? _actif;
  final _rechercheCtrl = TextEditingController();
  String _requete = '';

  @override
  void initState() {
    super.initState();
    context.read<StickersService>().assurer();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  /// L'onglet d'ouverture : les récents s'il y en a, sinon le premier pack.
  int _ouverture(StickersService s) {
    if (s.stickersRecents.isNotEmpty) return _recents;
    final packs = s.packsInstalles;
    return packs.isNotEmpty ? packs.first.id : _favoris;
  }

  Future<void> _basculerFavori(Sticker st) async {
    final s = context.read<StickersService>();
    final ajout = !s.estFavori(st.id);
    try {
      await s.basculerFavori(st.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(tr(context, ajout ? 'stickers_favori_ajoute' : 'stickers_favori_retire')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'stickers_erreur'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StickersService>();
    final langue = context.watch<LocaleController>().languageCode;
    final accent = widget.sombre ? AlanyaColors.terracottaNuit : accentOf(context);
    final muted = widget.sombre ? Colors.white60 : mutedOf(context, Colors.black54);
    final packs = s.packsInstalles;
    final actif = (_actif == null ||
            (_actif! > 0 && !packs.any((p) => p.id == _actif)))
        ? _ouverture(s)
        : _actif!;

    final List<Sticker> grille;
    String? vide;
    switch (actif) {
      case _recherche:
        grille = s.chercher(_requete);
        vide = _requete.trim().isEmpty ? null : 'stickers_aucun_resultat';
      case _recents:
        grille = s.stickersRecents;
        vide = 'stickers_vide_recents';
      case _favoris:
        grille = s.stickersFavoris;
        vide = 'stickers_vide_favoris';
      default:
        grille = packs.firstWhere((p) => p.id == actif).stickers;
    }

    Widget onglet(int id, Widget icone, String aide) {
      final choisi = actif == id;
      return Tooltip(
        message: aide,
        child: InkWell(
          onTap: () => setState(() => _actif = id),
          child: Container(
            width: 46,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(width: 2, color: choisi ? accent : Colors.transparent),
              ),
            ),
            alignment: Alignment.center,
            child: icone,
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    onglet(_recherche, Icon(Icons.search, size: 20, color: actif == _recherche ? accent : muted),
                        tr(context, 'stickers_chercher')),
                    onglet(_recents, Icon(Icons.access_time, size: 20, color: actif == _recents ? accent : muted),
                        tr(context, 'stickers_recents')),
                    onglet(_favoris, Icon(Icons.star_border, size: 21, color: actif == _favoris ? accent : muted),
                        tr(context, 'stickers_favoris')),
                    for (final p in packs)
                      onglet(
                        p.id,
                        p.vignette == null
                            ? Icon(Icons.collections_outlined, size: 20, color: muted)
                            : ImageSticker(url: p.vignette!, taille: 28),
                        p.nomDans(langue),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(context, 'stickers_boutique'),
                icon: Icon(Icons.add, color: muted),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BoutiqueStickersScreen()),
                ),
              ),
            ],
          ),
        ),
        if (actif == _recherche)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: TextField(
              controller: _rechercheCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _requete = v),
              style: TextStyle(color: widget.sombre ? Colors.white : null, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr(context, 'stickers_chercher_aide'),
                hintStyle: TextStyle(color: muted),
                prefixIcon: Icon(Icons.search, size: 20, color: muted),
              ),
            ),
          ),
        Expanded(
          child: grille.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(context, packs.isEmpty && actif > 0 ? 'stickers_aucun_pack' : (vide ?? 'stickers_chercher_aide')),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 84,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: grille.length,
                  itemBuilder: (_, i) {
                    final st = grille[i];
                    return InkWell(
                      key: ValueKey('sticker-${st.id}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onEnvoyer(st),
                      onLongPress: () => _basculerFavori(st),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ImageSticker(url: st.url, taille: 76),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
