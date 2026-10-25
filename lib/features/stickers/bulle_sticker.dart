import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/locale_controller.dart';
import '../../l10n/app_localizations.dart';
import 'boutique_stickers_screen.dart';
import 'image_sticker.dart';
import 'stickers_service.dart';

/// UN STICKER DANS LE FIL, comme chez WhatsApp : l'image seule, grande, SANS
/// bulle autour, l'heure (et les coches) dans une pastille en dessous.
///
/// Un toucher ouvre [ouvrirStickerRecu] : favori, et le pack d'où il vient.
class BulleSticker extends StatelessWidget {
  const BulleSticker({
    super.key,
    required this.charge,
    required this.timestamp,
    this.statusWidget,
    this.onLongPress,
  });

  final ChargeSticker charge;
  final String timestamp;
  final Widget? statusWidget;
  final VoidCallback? onLongPress;

  static const taille = 150.0;

  @override
  Widget build(BuildContext context) {
    final fond = Theme.of(context).brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.32);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          // Toute la case répond, même avant que l'image soit arrivée.
          behavior: HitTestBehavior.opaque,
          onTap: () => ouvrirStickerRecu(context, charge),
          onLongPress: onLongPress,
          child: Semantics(
            label: '${charge.emoji} ${tr(context, 'sticker')}'.trim(),
            image: true,
            child: ImageSticker(url: charge.url, taille: taille),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(timestamp, style: const TextStyle(fontSize: 10.5, color: Colors.white)),
              if (statusWidget != null) ...[const SizedBox(width: 3), statusWidget!],
            ],
          ),
        ),
      ],
    );
  }
}

/// La feuille d'un sticker reçu : l'image en grand, l'étoile des favoris, et
/// « Voir le pack » pour l'ajouter à son panneau — ce que propose WhatsApp.
/// Un sticker que le catalogue ne connaît plus (pack retiré, stickers fermés)
/// le dit, sans bouton.
Future<void> ouvrirStickerRecu(BuildContext context, ChargeSticker charge) {
  final s = context.read<StickersService>();
  s.assurer();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final svc = ctx.watch<StickersService>();
      final langue = ctx.watch<LocaleController>().languageCode;
      final sticker = svc.ouverts ? svc.sticker(charge.sid) : null;
      final pack = svc.ouverts ? svc.packParCode(charge.pack) : null;
      final favori = sticker != null && svc.estFavori(sticker.id);
      // La création de quelqu'un d'autre (25/10/2026) : ni au catalogue ni à
      // moi — on peut en garder une copie, comme WhatsApp, ou la signaler.
      final creationAutrui = svc.ouverts && sticker == null && charge.pack.startsWith('perso-');
      Future<void> agir(Future<void> Function() action, String reussite) async {
        final messager = ScaffoldMessenger.of(ctx);
        final ok = trLu(ctx, reussite);
        final erreur = trLu(ctx, 'stickers_erreur');
        try {
          await action();
          messager.showSnackBar(SnackBar(content: Text(ok)));
        } catch (_) {
          messager.showSnackBar(SnackBar(content: Text(erreur)));
        }
      }
      return SafeArea(
        // Défile sur un petit écran plutôt que de déborder.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ImageSticker(url: charge.url, taille: 180),
              const SizedBox(height: 8),
              if (pack != null)
                Text(
                  pack.nomDans(langue),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                )
              else if (svc.estMaCreation(charge.sid))
                Text(tr(ctx, 'stickers_creations'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))
              else if (!creationAutrui)
                Text(tr(ctx, 'stickers_indisponible'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (creationAutrui && svc.creation)
                ListTile(
                  key: const Key('sticker_enregistrer'),
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: Text(tr(ctx, 'stickers_enregistrer')),
                  onTap: () => agir(() => svc.copier(charge.sid), 'stickers_enregistre'),
                ),
              if (creationAutrui)
                ListTile(
                  key: const Key('sticker_signaler'),
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(tr(ctx, 'stickers_signaler')),
                  onTap: () => agir(() => svc.signaler(charge.assetId), 'stickers_signale'),
                ),
              if (sticker != null)
                ListTile(
                  key: const Key('sticker_favori'),
                  leading: Icon(favori ? Icons.star : Icons.star_border),
                  title: Text(tr(ctx, favori ? 'stickers_retirer_favori' : 'stickers_ajouter_favori')),
                  onTap: () async {
                    try {
                      await svc.basculerFavori(sticker.id);
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(trLu(ctx, 'stickers_erreur'))),
                        );
                      }
                    }
                  },
                ),
              if (pack != null)
                ListTile(
                  key: const Key('sticker_voir_pack'),
                  leading: const Icon(Icons.collections_outlined),
                  title: Text(tr(ctx, 'stickers_voir_pack')),
                  subtitle: svc.estInstalle(pack.id) ? Text(tr(ctx, 'stickers_deja_ajoute')) : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ouvrirPack(context, pack);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
