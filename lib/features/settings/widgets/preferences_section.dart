/// LES PRÉFÉRENCES, PARTAGÉES ENTRE LES RÉGLAGES ET L'ÉCRAN PROFIL.
///
/// Demande du user (28/09/2026) : l'écran Profil reprend toutes les options de
/// la catégorie « Préférences » des réglages. Elles vivent ICI, une seule fois :
/// deux copies finiraient par diverger — un réglage ajouté d'un côté, oublié de
/// l'autre.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data_saver_service.dart';
import '../../../core/locale_controller.dart';
import '../../../core/theme_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../screens/export_medias_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/repondeur_screen.dart';
import '../screens/ringtones_screen.dart';
import '../screens/translation_screen.dart';

/// Le titre d'une catégorie de réglages, en petites capitales.
class EnTeteReglages extends StatelessWidget {
  const EnTeteReglages(this.titre, {super.key, this.margeHorizontale = 16});

  final String titre;
  final double margeHorizontale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margeHorizontale, 20, margeHorizontale, 8),
      child: Text(
        titre.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: themed(
            context,
            light: AlanyaColors.grey500,
            dark: AlanyaColors.craie2,
          ),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Une ligne de réglage : icône teintée dans son carré, titre, sous-titre.
class TuileReglage extends StatelessWidget {
  const TuileReglage({
    super.key,
    required this.icone,
    required this.couleur,
    required this.titre,
    this.sousTitre,
    this.fin,
    this.onTap,
    this.margeHorizontale = 16,
  });

  final IconData icone;
  final Color couleur;
  final String titre;
  final String? sousTitre;
  final Widget? fin;
  final VoidCallback? onTap;

  /// 16 dans les réglages ; 0 dans le profil, dont la page a déjà sa marge.
  final double margeHorizontale;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: margeHorizontale, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: couleur, size: 22),
        ),
        title: Text(
          titre,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
        subtitle: sousTitre != null
            ? Text(
                sousTitre!,
                style: TextStyle(
                  fontSize: 12,
                  color: themed(
                    context,
                    light: AlanyaColors.grey500,
                    dark: AlanyaColors.craie2,
                  ),
                ),
              )
            : null,
        trailing: fin,
        onTap: onTap,
      ),
    );
  }
}

/// Le trait fin qui sépare deux lignes d’une carte de réglages.
Widget separateurReglage(BuildContext context) => Divider(
  height: 1,
  thickness: 0.5,
  indent: 72,
  color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
);

/// Le chevron « ouvre un écran », teinté selon le thème.
Widget chevronReglage(BuildContext context) => Icon(
  Icons.chevron_right,
  color: themed(context, light: Colors.grey, dark: AlanyaColors.craie2),
);

/// Les huit préférences : notifications, sonneries, répondeur, traduction,
/// export des médias, thème, économie de données, langue.
class PreferencesSection extends StatefulWidget {
  const PreferencesSection({
    super.key,
    this.margeHorizontale = 16,
    this.avecSeparateurs = false,
  });

  final double margeHorizontale;

  /// Un trait entre deux lignes : la liste groupée dans une carte (profil).
  final bool avecSeparateurs;

  @override
  State<PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends State<PreferencesSection> {
  bool _economie = DataSaverService.instance.isOn;

  Color get _muted =>
      themed(context, light: AlanyaColors.grey500, dark: AlanyaColors.craie2);
  Color get _mutedIcon =>
      themed(context, light: AlanyaColors.grey400, dark: AlanyaColors.craie2);
  Color get _accent => themed(
    context,
    light: AlanyaColors.terracotta,
    dark: AlanyaColors.terracottaNuit,
  );
  Color get _positive => themed(
    context,
    light: AlanyaColors.forest,
    dark: AlanyaColors.indigoLight,
  );
  Color get _chipOffBg => themed(
    context,
    light: AlanyaColors.grey200,
    dark: surfacesOf(context).surfaceHaute,
  );

  TuileReglage _tuile({
    required IconData icone,
    required Color couleur,
    required String titre,
    String? sousTitre,
    Widget? fin,
    VoidCallback? onTap,
  }) => TuileReglage(
    icone: icone,
    couleur: couleur,
    titre: titre,
    sousTitre: sousTitre,
    fin: fin,
    onTap: onTap,
    margeHorizontale: widget.margeHorizontale,
  );

  void _ouvrir(Widget ecran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

  @override
  Widget build(BuildContext context) {
    final localeCtrl = context.watch<LocaleController>();
    final themeCtrl = context.watch<ThemeController>();

    final tuiles = <Widget>[
      _tuile(
        icone: Icons.notifications_outlined,
        couleur: _accent,
        titre: tr(context, 'set_notifications'),
        sousTitre: tr(context, 'set_notifications_sub'),
        fin: chevronReglage(context),
        onTap: () => _ouvrir(const NotificationSettingsScreen()),
      ),
      _tuile(
        icone: Icons.library_music_outlined,
        couleur: _accent,
        titre: tr(context, 'set_ringtones'),
        sousTitre: tr(context, 'set_ringtones_sub'),
        fin: chevronReglage(context),
        onTap: () => _ouvrir(const RingtonesScreen()),
      ),
      _tuile(
        icone: Icons.voicemail_outlined,
        couleur: _accent,
        titre: tr(context, 'vm_title'),
        sousTitre: tr(context, 'vm_set_enable_hint'),
        fin: chevronReglage(context),
        onTap: () => _ouvrir(const RepondeurScreen()),
      ),
      _tuile(
        icone: Icons.translate,
        couleur: _accent,
        titre: tr(context, 'translated'),
        sousTitre: tr(context, 'set_translation_sub'),
        fin: chevronReglage(context),
        onTap: () => _ouvrir(const TranslationScreen()),
      ),
      // L'export a sa place APRÈS la traduction et AVANT l'apparence : c'est
      // un outil de données, comme les sonneries et la traduction, et non un
      // réglage de présentation.
      _tuile(
        icone: Icons.download_for_offline_outlined,
        couleur: _accent,
        titre: tr(context, 'exp_titre'),
        sousTitre: tr(context, 'exp_sub'),
        fin: chevronReglage(context),
        onTap: () => _ouvrir(const ExportMediasScreen()),
      ),
      _tuile(
        icone: ThemeController.icone(themeCtrl.choix),
        couleur: _accent,
        titre: tr(context, 'set_theme'),
        sousTitre: ThemeController.label(themeCtrl.choix),
        fin: chevronReglage(context),
        onTap: () => _choisirTheme(themeCtrl),
      ),
      _tuile(
        icone: _economie ? Icons.data_saver_on : Icons.data_saver_off,
        couleur: _economie ? _positive : _mutedIcon,
        titre: tr(context, 'set_data_saver'),
        sousTitre: _economie
            ? tr(context, 'set_data_saver_on')
            : tr(context, 'set_disabled_tap_on'),
        fin: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _economie ? _positive.withValues(alpha: 0.1) : _chipOffBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _economie ? "ON" : "OFF",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _economie ? _positive : _muted,
            ),
          ),
        ),
        onTap: () async {
          final v = !_economie;
          await DataSaverService.instance.setEnabled(v);
          if (mounted) setState(() => _economie = v);
        },
      ),
      _tuile(
        icone: Icons.language,
        couleur: _positive,
        titre: tr(context, 'language'),
        sousTitre: _nomLangue(localeCtrl),
        fin: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value:
                LocaleController.supported.any(
                  (l) => l.code == localeCtrl.languageCode,
                )
                ? localeCtrl.languageCode
                : 'fr',
            icon: Icon(Icons.expand_more, color: _mutedIcon, size: 20),
            items: LocaleController.supported.map((l) {
              return DropdownMenuItem(
                value: l.code,
                child: Text(
                  '${l.flag}  ${l.nativeName}',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (code) {
              if (code != null) localeCtrl.setLocale(code);
            },
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tuiles.length; i++) ...[
          if (avecSep(i)) separateurReglage(context),
          tuiles[i],
        ],
      ],
    );
  }

  bool avecSep(int i) => widget.avecSeparateurs && i > 0;

  String _nomLangue(LocaleController localeCtrl) {
    final match = LocaleController.supported.where(
      (l) => l.code == localeCtrl.languageCode,
    );
    return match.isNotEmpty ? match.first.nativeName : 'Français';
  }

  void _choisirTheme(ThemeController themeCtrl) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr(context, 'set_theme'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            ...ChoixTheme.values.map((c) {
              final selected = themeCtrl.choix == c;
              return ListTile(
                leading: Icon(ThemeController.icone(c), color: _accent),
                title: Text(ThemeController.label(c)),
                // Sans sous-titre, « Nuit » et « Noir » ne se distinguent pas.
                subtitle: Text(
                  ThemeController.description(c),
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                trailing: selected ? Icon(Icons.check, color: _accent) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  themeCtrl.setChoix(c);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
