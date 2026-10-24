import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/locale_controller.dart';
import '../../l10n/app_localizations.dart';
import 'image_sticker.dart';
import 'stickers_service.dart';

/// LA BOUTIQUE DE STICKERS, comme celle de WhatsApp : « Tous les stickers »
/// (le catalogue, un bouton pour ajouter chaque pack) et « Mes stickers »
/// (mes packs, à réordonner d'un glisser, à retirer).
class BoutiqueStickersScreen extends StatefulWidget {
  const BoutiqueStickersScreen({super.key});

  @override
  State<BoutiqueStickersScreen> createState() => _BoutiqueStickersScreenState();
}

class _BoutiqueStickersScreenState extends State<BoutiqueStickersScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StickersService>().rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'stickers_titre')),
          bottom: TabBar(
            tabs: [
              Tab(text: tr(context, 'stickers_tous')),
              Tab(text: tr(context, 'stickers_mes')),
            ],
          ),
        ),
        body: const TabBarView(children: [_TousLesPacks(), _MesPacks()]),
      ),
    );
  }
}

/// Ajoute ou retire un pack, et dit pourquoi si le serveur refuse.
Future<void> basculerPack(BuildContext context, PackStickers p) async {
  final s = context.read<StickersService>();
  final messager = ScaffoldMessenger.of(context);
  final erreur = tr(context, 'stickers_erreur');
  try {
    if (s.estInstalle(p.id)) {
      await s.retirer(p.id);
    } else {
      await s.installer(p.id);
    }
  } catch (_) {
    messager.showSnackBar(SnackBar(content: Text(erreur)));
  }
}

class _LignePack extends StatelessWidget {
  const _LignePack({super.key, required this.pack, this.fin, this.debut});

  final PackStickers pack;
  final Widget? fin;
  final Widget? debut;

  @override
  Widget build(BuildContext context) {
    final langue = context.watch<LocaleController>().languageCode;
    final details = [
      if (pack.auteur != null && pack.auteur!.isNotEmpty) pack.auteur!,
      tr(context, 'stickers_nombre', {'n': '${pack.stickers.length}'}),
    ].join(' · ');
    return ListTile(
      key: ValueKey('pack-${pack.id}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (debut != null) debut!,
          pack.vignette == null
              ? const SizedBox.square(dimension: 48, child: Icon(Icons.collections_outlined))
              : ImageSticker(url: pack.vignette!, taille: 48),
        ],
      ),
      title: Text(pack.nomDans(langue), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: fin,
      onTap: () => ouvrirPack(context, pack),
    );
  }
}

class _TousLesPacks extends StatelessWidget {
  const _TousLesPacks();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StickersService>();
    if (s.catalogue.isEmpty) {
      return Center(child: Text(tr(context, 'stickers_catalogue_vide')));
    }
    return ListView(
      children: [
        for (final p in s.catalogue)
          _LignePack(
            pack: p,
            fin: s.estInstalle(p.id)
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : IconButton(
                    key: ValueKey('ajouter-${p.id}'),
                    tooltip: tr(context, 'stickers_ajouter'),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    onPressed: () => basculerPack(context, p),
                  ),
          ),
      ],
    );
  }
}

class _MesPacks extends StatelessWidget {
  const _MesPacks();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StickersService>();
    final packs = s.packsInstalles;
    if (packs.isEmpty) {
      return Center(child: Text(tr(context, 'stickers_aucun_pack')));
    }
    return ReorderableListView(
      buildDefaultDragHandles: false,
      onReorder: (de, vers) {
        final ids = [for (final p in packs) p.id];
        final id = ids.removeAt(de);
        ids.insert(vers > de ? vers - 1 : vers, id);
        s.ordonner(ids).catchError((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'stickers_erreur'))),
            );
          }
        });
      },
      children: [
        for (final (i, p) in packs.indexed)
          _LignePack(
            key: ValueKey('mien-${p.id}'),
            pack: p,
            debut: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle),
              ),
            ),
            fin: IconButton(
              key: ValueKey('retirer-${p.id}'),
              tooltip: tr(context, 'stickers_retirer'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => basculerPack(context, p),
            ),
          ),
      ],
    );
  }
}

/// L'APERÇU D'UN PACK : tous ses stickers, et « Ajouter » ou « Retirer ».
/// Ouvert depuis la boutique, ou depuis un sticker reçu (« Voir le pack »).
Future<void> ouvrirPack(BuildContext context, PackStickers pack) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, defilement) {
        final s = ctx.watch<StickersService>();
        final langue = ctx.watch<LocaleController>().languageCode;
        final installe = s.estInstalle(pack.id);
        return Column(
          children: [
            ListTile(
              title: Text(pack.nomDans(langue), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if (pack.descriptionDans(langue) case final String d) d,
                tr(ctx, 'stickers_nombre', {'n': '${pack.stickers.length}'}),
              ].join('\n')),
            ),
            Expanded(
              child: GridView.builder(
                controller: defilement,
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 90,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: pack.stickers.length,
                itemBuilder: (_, i) => ImageSticker(url: pack.stickers[i].url, taille: 84),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: installe
                      ? OutlinedButton(
                          key: const Key('pack_retirer'),
                          onPressed: () => basculerPack(ctx, pack),
                          child: Text(tr(ctx, 'stickers_retirer')),
                        )
                      : FilledButton(
                          key: const Key('pack_ajouter'),
                          onPressed: () => basculerPack(ctx, pack),
                          child: Text(tr(ctx, 'stickers_ajouter')),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
