/// L'ÉCRAN ENTRE LA CONNEXION ET LA SESSION : l'historique chiffré revient.
///
/// 🐛 « QUAND JE ME CONNECTE SUR UN NOUVEAU TÉLÉPHONE, L'ARCHIVE NE SE CHARGE
/// PAS » (user, 28/09/2026). La restauration tournait en fond, invisible, et
/// chaque échec était avalé : un mot de passe changé, une archive protégée par
/// la seule clé de récupération, une coupure réseau — même résultat, rien.
///
/// Demande du user : un écran entre la connexion et la session, qui récupère
/// l'archive, la déchiffre, la range en local, et MONTRE où il en est.
///
/// ⚠️ « CONTINUER EN ARRIÈRE-PLAN » (choix du user) : un long historique ne
/// doit pas bloquer l'entrée. La restauration continue alors en fond — elle
/// ne dépend pas de cet écran — et les conversations se remplissent à mesure
/// (`E2eeSauvegarde.restaurations`).
///
/// ⚠️ LE MOT DE PASSE N'EST ÉCRIT NULLE PART : il traverse cet écran, le temps
/// d'ouvrir la serrure.
library;

import '../../../l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/e2ee/e2ee_fournisseur.dart';
import '../auth_controller.dart';
import '../../../services/e2ee/e2ee_sauvegarde.dart';
import '../restauration_progression.dart';

class RestaurationScreen extends StatefulWidget {
  const RestaurationScreen({super.key, required this.motDePasse});

  final String motDePasse;

  @override
  State<RestaurationScreen> createState() => _RestaurationScreenState();
}

class _RestaurationScreenState extends State<RestaurationScreen> {
  ProgressionRestauration _progression = const ProgressionRestauration(
    EtapeRestauration.ouverture,
    0,
  );

  /// L'archive ne s'est pas ouverte avec le mot de passe, mais elle a une clé
  /// de récupération : on la propose, sans bloquer (27/11/2026).
  bool _proposerCle = false;
  final TextEditingController _mots = TextEditingController();
  bool _ouvertureEnCours = false;
  String? _erreur;

  @override
  void dispose() {
    _mots.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lancer());
  }

  /// La pile de chiffrement du compte qui vient de se connecter.
  ///
  /// ⚠️ ELLE PEUT MANQUER UN INSTANT : `main.dart` la bâtit quand
  /// `AuthController` change, à la reconstruction suivante. On l'attend un
  /// peu, sans jamais bloquer : sans elle, on entre sans restaurer.
  Future<PileE2ee?> _pile() async {
    for (var i = 0; i < 50; i++) {
      if (!mounted) return null;
      final pile = context.e2ee;
      if (pile != null) return pile;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _lancer() async {
    setState(() {
      _progression = const ProgressionRestauration(
        EtapeRestauration.ouverture,
        0,
      );
    });
    final pile = await _pile();
    if (!mounted) return;
    if (pile == null) {
      _entrer();
      return;
    }
    final r = await pile.sauvegarde.ouvrirEtRestaurer(
      widget.motDePasse,
      pile.coffre,
      suivi: (p) {
        if (mounted) setState(() => _progression = p);
      },
    );
    /*
     * 🔴 LA CLÉ DU COMPTE TOUT DE SUITE (chiffrement des groupes v2, 13/11/2026).
     *
     * 🐛 Un compte neuf, mis hors ligne juste après l'inscription puis ajouté à
     * un groupe chiffré, ne pouvait jamais lire ce groupe sans qu'un membre
     * revienne en ligne. Sa clé de compte n'était tirée qu'au démarrage, AVANT
     * que cet écran crée l'archive : sans clé maîtresse, rien. Sans clé de
     * compte sur le serveur, personne ne peut lui emballer la clé du groupe.
     *
     * La clé maîtresse vient d'être posée : on crée (ou reprend) la clé du
     * compte et on relit les groupes. En fond, sans retarder l'entrée.
     */
    unawaited(pile.fil.groupe.restaurerTous());
    // L'utilisateur a pu choisir « Continuer en arrière-plan » : l'écran n'est
    // plus là, la restauration, elle, est allée au bout.
    if (!mounted) return;
    if (r.issue == IssueConnexion.restauree ||
        r.issue == IssueConnexion.rienARestaurer) {
      _entrer();
      return;
    }

    /*
     * 🔴 UNE SAUVEGARDE QUI NE S'OUVRE PAS N'ARRÊTE PLUS PERSONNE (décision du
     * user, 12/10/2026 : « l'utilisateur lambda ne doit même pas savoir que
     * l'application est chiffrée ; l'obliger à saisir des mots de passe pour
     * voir ses fichiers, c'est trop »).
     *
     * On entrait ici dans un écran qui demandait les douze mots de la clé de
     * récupération, juste après la connexion. Pour quelqu'un qui veut lire ses
     * messages, c'est une porte fermée à l'endroit exact où il croyait entrer —
     * et il ne comprend même pas de quoi on lui parle.
     *
     * ⚠️ RIEN N'EST PERDU, ET C'EST CE QUI REND CE SILENCE ACCEPTABLE :
     *   · les messages à venir arrivent normalement, par leurs enveloppes —
     *     la sauvegarde ne sert QU'À L'HISTORIQUE ANTÉRIEUR à cet appareil ;
     *   · le rattrapage (`_completerParArchive`) retente à chaque ouverture de
     *     conversation, et réussira dès que la clé sera là ;
     *   · la clé de récupération reste offerte dans Réglages › Sauvegarde
     *     chiffrée, pour qui la cherche.
     *
     * ⚠️ `fermee` N'EST PAS `echec` : la première est définitive (mot de passe
     * changé, archive protégée par la seule clé de récupération), la seconde
     * est passagère (réseau). Les deux entrent — mais seule la seconde mérite
     * qu'on retente, et le rattrapage s'en charge.
     *
     * 🔴 SAUF UNE PROPOSITION, DISCRÈTE (demande du user, 27/11/2026) : si
     * l'archive est fermée ET qu'elle a une clé de récupération, on la
     * propose — « Plus tard » entre aussitôt. Sans clé, rien à proposer.
     */
    if (r.issue == IssueConnexion.fermee &&
        !await _propositionReportee() &&
        await pile.sauvegarde.aUneCleDeRecuperation()) {
      if (mounted) setState(() => _proposerCle = true);
      return;
    }
    _entrer();
  }

  /*
   * « Plus tard » sur la proposition des 12 mots : on ne la refait pas avant
   * sept jours sur cet appareil (27/11/2026).
   */
  static const _report = Duration(days: 7);

  String? _cleReport() {
    final moi = context.read<AuthController>().user?.id;
    return moi == null ? null : 'proposition_cle_reportee_$moi';
  }

  Future<bool> _propositionReportee() async {
    final cle = _cleReport();
    if (cle == null) return false;
    final quand = (await SharedPreferences.getInstance()).getInt(cle);
    return quand != null &&
        DateTime.now().millisecondsSinceEpoch - quand < _report.inMilliseconds;
  }

  Future<void> _reporterEtEntrer() async {
    final cle = _cleReport();
    if (cle != null) {
      await (await SharedPreferences.getInstance())
          .setInt(cle, DateTime.now().millisecondsSinceEpoch);
    }
    _entrer();
  }

  /// Les 12 mots saisis : on ouvre, on RELIE l'archive au mot de passe qu'on
  /// vient de taper (les appareils suivants s'ouvriront avec lui), on restaure.
  Future<void> _ouvrirParCle() async {
    final saisie = _mots.text.trim();
    if (saisie.isEmpty || _ouvertureEnCours) return;
    setState(() {
      _ouvertureEnCours = true;
      _erreur = null;
    });
    final pile = context.e2ee;
    if (pile == null) {
      _entrer();
      return;
    }
    final ok = await pile.sauvegarde.ouvrirParRecuperation(
      saisie,
      pile.coffre,
      motDePasse: widget.motDePasse,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _ouvertureEnCours = false;
        _erreur = tr(context, 'arch_cle_refusee');
      });
      return;
    }
    setState(() => _proposerCle = false);
    try {
      await pile.sauvegarde.restaurer(suivi: (p) {
        if (mounted) setState(() => _progression = p);
      });
    } catch (_) {}
    unawaited(pile.fil.groupe.restaurerTous());
    _entrer();
  }

  void _entrer() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Le retour système équivaut à « Continuer en arrière-plan » : on ne
      // revient pas à l'écran de connexion, la session est déjà ouverte.
      canPop: false,
      onPopInvokedWithResult: (aPoppe, _) {
        if (!aPoppe) _entrer();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ⚠️ PAS DE CADENAS : l'icône parlerait de ce dont on a
                // justement décidé de ne plus parler. Un nuage qui descend dit
                // la seule chose vraie pour celui qui attend — ça arrive.
                Icon(
                  Icons.cloud_download_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  tr(context, 'rest_titre'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (_proposerCle) ..._propositionCle(theme) else ..._enCours(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _propositionCle(ThemeData theme) => [
        Text(
          tr(context, 'arch_cle_proposee_titre'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'arch_cle_proposee_texte'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _mots,
          minLines: 2,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr(context, 'arch_cle_saisie'),
            border: const OutlineInputBorder(),
            errorText: _erreur,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _ouvertureEnCours ? null : _ouvrirParCle,
          child: _ouvertureEnCours
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr(context, 'arch_cle_restaurer')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _ouvertureEnCours ? null : _reporterEtEntrer,
          child: Text(tr(context, 'arch_plus_tard')),
        ),
      ];

  List<Widget> _enCours(ThemeData theme) {
    final texteCompteur = compteur(
      _progression,
      blocs: tr(context, 'rest_blocs'),
      messages: tr(context, 'rest_messages'),
    );
    return [
      /*
       * ⚠️ PAS UN MOT DE « CHIFFRÉ » ICI (décision du user, 12/10/2026).
       * Celui qui vient de se connecter veut ses messages ; lui expliquer la
       * cryptographie à cet instant ne l'aide pas, et l'inquiète. Ce qu'il a
       * besoin de savoir, c'est que ça arrive et que ça ne dépend pas de lui.
       */
      Text(
        tr(context, 'rest_sous'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 32),
      Text(
        tr(context, 'rest_etape_${_progression.etape.name}'),
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fractionGlobale(_progression),
          minHeight: 8,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 20,
        child: texteCompteur == null
            ? null
            : Text(
                texteCompteur,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
      ),
      const SizedBox(height: 28),
      OutlinedButton(
        onPressed: _entrer,
        child: Text(tr(context, 'rest_arriere_plan')),
      ),
      const SizedBox(height: 8),
      Text(
        tr(context, 'rest_note'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

}
