import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:provider/provider.dart';

import '../../../core/app_snackbar.dart';
import '../../../core/locale_controller.dart';
import '../../../core/traduction_appareil.dart';
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
      showAppSnackBar("Installation impossible");
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
        title: Text("Retirer « $nom » ?"),
        content: Text(
          cible
              // Retirer la langue de l'application casse TOUTES les traductions,
              // pas seulement celles depuis cette langue : elle est la cible de
              // chacune d'elles.
              ? "C'est la langue de l'application : sans elle, plus aucun "
                    "message ne pourra être traduit. Il faudra la réinstaller."
              : "L'espace disque sera libéré. Il faudra la retélécharger pour "
                    "traduire à nouveau depuis cette langue.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Retirer"),
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
      showAppSnackBar("Suppression impossible");
      return;
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Traduction"),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: Column(
          children: [
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
          "La traduction hors ligne n'existe que sur téléphone.",
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
            "La traduction se fait sur ton téléphone : aucun message n'est "
            "envoyé sur Internet. Chaque langue s'installe une fois, puis "
            "fonctionne hors ligne.",
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.translate, size: 16, color: accentOf(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Traduire vers ${nomAutonyme(_langueCible)} — il faut CETTE "
                  "langue et celle du message.",
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
          hintText: "Chercher une langue (nom, code, anglais)",
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
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text("Aucune langue ne correspond.")),
          ),
        if (presentes.isNotEmpty) ...[
          _titreSection("Installées (${presentes.length})"),
          ...presentes.map((l) => _ligne(l, installee: true)),
        ],
        if (absentes.isNotEmpty) ...[
          _titreSection("Disponibles"),
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
      subtitle: Text(
        estCible ? "$code · langue de l'application" : "$code · ${langue.name}",
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
              tooltip: installee ? "Retirer" : "Installer",
              onPressed: () =>
                  installee ? _retirer(langue) : _installer(langue),
            ),
    );
  }
}
