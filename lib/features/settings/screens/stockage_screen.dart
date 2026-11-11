import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/locale_controller.dart';
import '../../../core/stockage_local.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';

/// PARAMÈTRES › STOCKAGE (11/11/2026), repris de l'application de référence :
/// la place qu'occupe l'application sur ce téléphone, poste par poste, et de
/// quoi en libérer — le cache des médias (tout se retélécharge) et les
/// fichiers temporaires.
class StockageScreen extends StatefulWidget {
  const StockageScreen({super.key});

  @override
  State<StockageScreen> createState() => _StockageScreenState();
}

class _StockageScreenState extends State<StockageScreen> {
  RepartitionStockage? _repartition;
  bool _mesure = false;
  bool _vidage = false;

  @override
  void initState() {
    super.initState();
    _mesurer();
  }

  Future<void> _mesurer() async {
    setState(() => _mesure = true);
    try {
      final r = await StockageLocal.mesurer();
      if (mounted) setState(() => _repartition = r);
    } finally {
      if (mounted) setState(() => _mesure = false);
    }
  }

  String _taille(int octets) => StockageLocal.formater(
        octets,
        tr(context, 'stock_unites'),
        context.read<LocaleController>().languageCode,
      );

  Future<void> _viderMedias() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'stock_vider_medias')),
        content: Text(tr(ctx, 'stock_vider_medias_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'stock_vider')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final fait = tr(context, 'stock_vider_medias_ok');
    setState(() => _vidage = true);
    try {
      await StockageLocal.viderMedias();
      showAppSnackBar(fait);
      await _mesurer();
    } finally {
      if (mounted) setState(() => _vidage = false);
    }
  }

  /// Sans confirmation, comme chez eux : rien d'utile ne s'y perd.
  Future<void> _viderTemporaires() async {
    final fait = tr(context, 'stock_vider_temp_ok');
    setState(() => _vidage = true);
    try {
      await StockageLocal.viderTemporaires();
      showAppSnackBar(fait);
      await _mesurer();
    } finally {
      if (mounted) setState(() => _vidage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    final r = _repartition;
    return Scaffold(
      backgroundColor: s.fond,
      appBar: backAppBar(context, tr(context, 'stock_titre')),
      body: r == null
          ? Center(child: CircularProgressIndicator(color: accentOf(context)))
          : RefreshIndicator(
              onRefresh: _mesurer,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _carteTotal(r),
                  const SizedBox(height: 24),
                  _titre(tr(context, 'stock_repartition')),
                  Container(
                    decoration: BoxDecoration(
                      color: s.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        for (final p in _postes(r))
                          ListTile(
                            leading: Icon(p.icone, color: p.couleur),
                            title: Text(p.titre),
                            trailing: Text(
                              _taille(p.octets),
                              style: TextStyle(color: mutedOf(context, Colors.black54)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _vidage ? null : _viderMedias,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr(context, 'stock_vider_medias')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _vidage ? null : _viderTemporaires,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: Text(tr(context, 'stock_vider_temp')),
                  ),
                ],
              ),
            ),
    );
  }

  List<_Poste> _postes(RepartitionStockage r) => [
        _Poste(Icons.perm_media_outlined, accentOf(context), tr(context, 'stock_medias'), r.medias),
        _Poste(Icons.storage_outlined, AlanyaColors.gold, tr(context, 'stock_base'), r.base),
        _Poste(Icons.folder_outlined, positiveOf(context), tr(context, 'stock_temp'), r.temporaires),
        _Poste(Icons.insert_drive_file_outlined, mutedOf(context, Colors.black38), tr(context, 'stock_autres'), r.autres),
      ];

  Widget _titre(String texte) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          texte,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: mutedOf(context, Colors.black54),
          ),
        ),
      );

  Widget _carteTotal(RepartitionStockage r) {
    final s = surfacesOf(context);
    final postes = _postes(r).where((p) => p.octets > 0).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'stock_utilise'),
                  style: TextStyle(color: mutedOf(context, Colors.black54)),
                ),
              ),
              if (_mesure)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accentOf(context)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _taille(r.total),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          if (postes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (final p in postes)
                      Expanded(
                        // `flex` est un entier : en kilo-octets, pour ne pas
                        // dépasser ses bornes sur un gros cache.
                        flex: (p.octets ~/ 1024).clamp(1, 1 << 30),
                        child: ColoredBox(color: p.couleur),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Poste {
  const _Poste(this.icone, this.couleur, this.titre, this.octets);
  final IconData icone;
  final Color couleur;
  final String titre;
  final int octets;
}
