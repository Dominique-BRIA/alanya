import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/locale_controller.dart';
import '../../../core/traduction_appareil.dart';
import '../../../core/traduction_auto.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/dialogues_traduction.dart';
import '../../../widgets/motif_background.dart';

/// Réglages ▸ Traduction : installer et retirer les langues hors ligne.
///
/// Sans cet écran, le seul moyen d'installer une langue était de tomber sur un
/// message écrit dedans — impossible de préparer un voyage, impossible de
/// récupérer l'espace disque, et aucun moyen de savoir ce qui était déjà là.
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final _rechercheCtrl = TextEditingController();

  Set<String>? _installees;
  String _recherche = "";

  /// Les codes dont une installation ou un retrait est en cours. Un ensemble
  /// et non un booléen : deux langues peuvent travailler en même temps, et
  /// bloquer toute la liste pour un téléchargement de 40 Mo serait pénible.
  final Set<String> _enCours = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    // Les 59 sondages repartent de zéro : un modèle a pu être évincé par le
    // système depuis la dernière visite.
    reevaluerModeles();
    final installees = await languesInstallees();
    if (!mounted) return;
    setState(() => _installees = installees);
  }

  String get _langueCible =>
      normaliserLangue(context.read<LocaleController>().languageCode);

  Future<void> _installer(TranslateLanguage langue) async {
    final nom = nomAutonyme(langue.bcpCode);
    if (!await confirmerInstallationLangues(context, nom)) return;
    if (!mounted) return;
    setState(() => _enCours.add(langue.bcpCode));
    var ok = await telechargerLangue(langue);
    // Échec en Wi-Fi seul : on expose la restriction au lieu de laisser
    // l'utilisateur devant un « impossible » sans recours.
    if (!ok && wifiExige && mounted && await proposerDonneesMobiles(context)) {
      ok = await telechargerLangue(langue, wifiSeulement: false);
    }
    if (!mounted) return;
    setState(() => _enCours.remove(langue.bcpCode));
    if (!ok) {
      showAppSnackBar(tr(context, 'trans_install_failed'));
      return;
    }
    await _charger();
  }

  Future<void> _retirer(TranslateLanguage langue) async {
    final nom = nomAutonyme(langue.bcpCode);
    final cible = langue.bcpCode == _langueCible;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'trans_remove_q', {'nom': nom})),
        content: Text(
          cible
              // Retirer la langue de l'application casse TOUTES les traductions,
              // pas seulement celles depuis cette langue : elle est la cible de
              // chacune d'elles.
              ? tr(context, 'trans_remove_app_lang_body')
              : tr(context, 'trans_remove_lang_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(context, 'remove')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enCours.add(langue.bcpCode));
    final retire = await supprimerLangue(langue);
    if (!mounted) return;
    setState(() => _enCours.remove(langue.bcpCode));
    if (!retire) {
      showAppSnackBar(tr(context, 'delete_failed'));
      return;
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'translated')),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: Column(
          children: [
            _interrupteurAuto(),
            _entete(),
            _champRecherche(),
            Expanded(
              child: RefreshIndicator(onRefresh: _charger, child: _corps()),
            ),
          ],
        ),
      ),
    );
  }

  /// L'interrupteur « Traduction automatique », en TÊTE de l'écran.
  ///
  /// 🔴 ICI ET NON DANS LA LISTE DES RÉGLAGES : il ne se comprend qu'à côté des
  /// langues installées, dont il dépend entièrement. Un message ne sera traduit
  /// tout seul que si son couple de langues est déjà là — l'écran qui l'annonce
  /// doit être celui qui permet de l'installer.
  ///
  /// ⚠️ MASQUÉ SI LE MOTEUR N'EXISTE PAS (web) : proposer d'automatiser ce que
  /// la plateforme ne sait pas faire serait une promesse vide.
  Widget _interrupteurAuto() {
    if (!moteurAppareilPresent) return const SizedBox.shrink();
    final muted = themed(
      context,
      light: Colors.black54,
      dark: AlanyaColors.craie2,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: TraductionAuto.instance.active,
      builder: (_, actif, __) => SwitchListTile(
        value: actif,
        onChanged: (v) => TraductionAuto.instance.definir(v),
        title: Text(tr(context, 'trans_auto')),
        subtitle: Text(
          actif
              // Ce que la fonction NE FAIT PAS est aussi important : sans cette
              // phrase, un message resté dans sa langue passerait pour une
              // panne, alors que son modèle n'est simplement pas installé.
              ? tr(context, 'trans_auto_on')
              : tr(context, 'trans_auto_off'),
          style: TextStyle(color: muted, fontSize: 12),
        ),
        secondary: Icon(Icons.translate, color: accentOf(context)),
      ),
    );
  }

  Widget _entete() {
    final muted = themed(
      context,
      light: Colors.black54,
      dark: AlanyaColors.craie2,
    );
    if (!moteurAppareilPresent) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          tr(context, 'trans_mobile_only'),
          style: TextStyle(color: muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'trans_on_device'),
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.translate, size: 16, color: accentOf(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(context, 'trans_target_hint', {'langue': nomAutonyme(_langueCible)}),
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _champRecherche() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _rechercheCtrl,
        onChanged: (v) => setState(() => _recherche = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: tr(context, 'trans_search_hint'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  Widget _corps() {
    if (!moteurAppareilPresent) return const SizedBox.shrink();
    final installees = _installees;
    if (installees == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final toutes = languesTraduisibles().where(
      (l) => langueCorrespond(l, _recherche),
    );
    final presentes = toutes
        .where((l) => installees.contains(l.bcpCode))
        .toList();
    final absentes = toutes
        .where((l) => !installees.contains(l.bcpCode))
        .toList();

    return ListView(
      // `always` : sans ça, une liste plus courte que l'écran ne se tire pas,
      // et le rafraîchissement devient inatteignable après un filtre.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (presentes.isEmpty && absentes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr(context, 'trans_no_match'))),
          ),
        if (presentes.isNotEmpty) ...[
          _titreSection(tr(context, 'trans_installed_n', {'n': '${presentes.length}'})),
          ...presentes.map((l) => _ligne(l, installee: true)),
        ],
        if (absentes.isNotEmpty) ...[
          _titreSection(tr(context, 'trans_available')),
          ...absentes.map((l) => _ligne(l, installee: false)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _titreSection(String titre) {
    final muted = themed(
      context,
      light: Colors.black54,
      dark: AlanyaColors.craie2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        titre,
        style: TextStyle(
          color: muted,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _ligne(TranslateLanguage langue, {required bool installee}) {
    final code = langue.bcpCode;
    final occupee = _enCours.contains(code);
    final estCible = code == _langueCible;
    return ListTile(
      title: Text(
        nomAutonyme(code),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      // Pendant l'installation, la ligne dit ce que le rond tournant ne dit
      // pas : ML Kit n'expose aucun avancement, donc ni pourcentage ni durée.
      // Sans ce mot, un rond qui tourne longtemps se lit comme un blocage.
      subtitle: Text(
        occupee
            ? tr(context, 'trans_installing')
            : estCible
            ? tr(context, 'trans_app_lang', {'code': code})
            : "$code · ${langue.name}",
      ),
      trailing: occupee
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(
                installee ? Icons.delete_outline : Icons.download_outlined,
                color: installee ? null : accentOf(context),
              ),
              tooltip: installee ? tr(context, 'remove') : tr(context, 'install_action'),
              onPressed: () =>
                  installee ? _retirer(langue) : _installer(langue),
            ),
    );
  }
}
