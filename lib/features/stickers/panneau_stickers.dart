import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/locale_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/alanya_theme.dart';
import 'boutique_stickers_screen.dart';
import 'creer_sticker_screen.dart';
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

/// « Mes créations » (25/10/2026) : une case « Créer » en tête de la grille.
const _creations = -4;

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

  /// Crée un sticker et l'ENVOIE aussitôt, comme WhatsApp.
  Future<void> _creer() async {
    final cree = await CreerStickerScreen.ouvrir(context);
    if (cree != null && mounted) {
      setState(() => _actif = _creations);
      widget.onEnvoyer(cree);
    }
  }

  /// Appui long sur une de MES créations : favori, ou suppression.
  Future<void> _optionsCreation(Sticker st) async {
    final s = context.read<StickersService>();
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImageSticker(url: st.url, taille: 120),
            ListTile(
              leading: Icon(s.estFavori(st.id) ? Icons.star : Icons.star_border),
              title: Text(tr(ctx, s.estFavori(st.id) ? 'stickers_retirer_favori' : 'stickers_ajouter_favori')),
              onTap: () => Navigator.pop(ctx, 'favori'),
            ),
            ListTile(
              key: const Key('creation_supprimer'),
              leading: const Icon(Icons.delete_outline),
              title: Text(tr(ctx, 'stickers_supprimer')),
              onTap: () => Navigator.pop(ctx, 'supprimer'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choix == null) return;
    if (choix == 'favori') return _basculerFavori(st);
    final messager = ScaffoldMessenger.of(context);
    final erreur = trLu(context, 'stickers_erreur');
    try {
      await s.supprimerCreation(st.id);
    } catch (_) {
      messager.showSnackBar(SnackBar(content: Text(erreur)));
    }
  }

  Future<void> _basculerFavori(Sticker st) async {
    final s = context.read<StickersService>();
    final ajout = !s.estFavori(st.id);
    try {
      await s.basculerFavori(st.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(trLu(context, ajout ? 'stickers_favori_ajoute' : 'stickers_favori_retire')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trLu(context, 'stickers_erreur'))),
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
      case _creations:
        grille = s.creations?.stickers ?? const [];
        vide = null;
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
                    if (s.creation)
                      onglet(_creations, Icon(Icons.brush_outlined, size: 20, color: actif == _creations ? accent : muted),
                          tr(context, 'stickers_creations')),
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
          child: grille.isEmpty && actif != _creations
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
                  // « Mes créations » commence par la case « Créer ».
                  itemCount: grille.length + (actif == _creations ? 1 : 0),
                  itemBuilder: (_, n) {
                    if (actif == _creations && n == 0) {
                      return InkWell(
                        key: const Key('sticker_creer'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: _creer,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: muted.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, color: accent),
                              const SizedBox(height: 4),
                              Text(tr(context, 'stickers_creer'),
                                  style: TextStyle(fontSize: 12, color: accent)),
                            ],
                          ),
                        ),
                      );
                    }
                    final st = grille[actif == _creations ? n - 1 : n];
                    return InkWell(
                      key: ValueKey('sticker-${st.id}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onEnvoyer(st),
                      onLongPress: () => s.estMaCreation(st.id) ? _optionsCreation(st) : _basculerFavori(st),
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
