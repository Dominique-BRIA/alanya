import 'package:flutter/material.dart';

import '../../../core/data_saver_service.dart';
import '../../../core/telechargement_auto.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/back_app_bar.dart';

/// RÉGLAGES › TÉLÉCHARGEMENT DES MÉDIAS (14/11/2026, demande du user :
/// « l'économie de données ne fonctionne pas »).
///
/// Trois décisions, lues par `core/telechargement_auto.dart` :
///   - « Wi-Fi uniquement » (allumé par défaut, comme l'application de
///     référence) : sur données mobiles, rien ne se télécharge tout seul ;
///   - « Économie de données » : la même chose, plus les modèles de traduction
///     hors ligne qui attendent le Wi-Fi ;
///   - les familles qui se téléchargent d'office : photos et messages vocaux.
///
/// ⚠️ PAS DE CASE « VIDÉOS » NI « DOCUMENTS » : sur le mobile, ils attendent
/// déjà un toucher (une vidéo ou un document chiffrés ne viennent jamais
/// d'office). Un interrupteur qui ne change rien serait un mensonge ; la note
/// en bas de l'écran le dit.
class TelechargementMediasScreen extends StatefulWidget {
  const TelechargementMediasScreen({super.key});

  @override
  State<TelechargementMediasScreen> createState() => _TelechargementMediasScreenState();
}

class _TelechargementMediasScreenState extends State<TelechargementMediasScreen> {
  final _reglages = TelechargementAuto.instance;

  @override
  void initState() {
    super.initState();
    _reglages.addListener(_redessiner);
    DataSaverService.instance.enabled.addListener(_redessiner);
  }

  @override
  void dispose() {
    _reglages.removeListener(_redessiner);
    DataSaverService.instance.enabled.removeListener(_redessiner);
    super.dispose();
  }

  void _redessiner() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final economie = DataSaverService.instance.isOn;
    Widget titre(String cle) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(tr(context, cle),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
        );
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'dl_titre')),
      body: ListView(
        children: [
          titre('dl_reseau'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_rounded),
            title: Text(tr(context, 'dl_wifi')),
            subtitle: Text(tr(context, 'dl_wifi_sub')),
            value: _reglages.wifiSeulement,
            onChanged: (v) => _reglages.changerWifiSeulement(v),
          ),
          SwitchListTile(
            secondary: Icon(economie ? Icons.data_saver_on : Icons.data_saver_off),
            title: Text(tr(context, 'set_data_saver')),
            subtitle: Text(tr(context, 'dl_eco_sub')),
            value: economie,
            onChanged: (v) => DataSaverService.instance.setEnabled(v),
          ),
          titre('dl_auto'),
          SwitchListTile(
            secondary: const Icon(Icons.photo_outlined),
            title: Text(tr(context, 'dl_photos')),
            value: _reglages.famille(FamilleMedia.photo),
            onChanged: (v) => _reglages.changerFamille(FamilleMedia.photo, v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.mic_none_rounded),
            title: Text(tr(context, 'dl_vocaux')),
            value: _reglages.famille(FamilleMedia.audio),
            onChanged: (v) => _reglages.changerFamille(FamilleMedia.audio, v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr(context, 'dl_note'),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
