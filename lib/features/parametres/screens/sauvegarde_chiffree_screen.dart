/// LES RÉGLAGES DE LA SAUVEGARDE CHIFFRÉE — le pendant mobile du panneau web.
///
/// 🔴 CET ÉCRAN DOIT DIRE CE QU'IL COÛTE AVANT DE LE FAIRE COÛTER. Une
/// sauvegarde dont on perd les clés n'est pas « indisponible » : elle est
/// DÉTRUITE, et personne — nous compris — ne la rouvrira. Une interface qui ne
/// l'annonce qu'après coup a menti par omission.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_snackbar.dart';
import '../../../services/e2ee/e2ee_fournisseur.dart';
import '../../../services/e2ee/e2ee_serrures.dart';

class SauvegardeChiffreeScreen extends StatefulWidget {
  const SauvegardeChiffreeScreen({super.key});

  @override
  State<SauvegardeChiffreeScreen> createState() =>
      _SauvegardeChiffreeScreenState();
}

class _SauvegardeChiffreeScreenState extends State<SauvegardeChiffreeScreen> {
  bool _charge = true;
  bool _occupe = false;
  bool _refusee = false;
  List<Serrure> _serrures = const [];

  /// ⚠️ ON NE PROPOSE PAS CE QU'ON NE PEUT PAS TENIR : sans biométrie ni code de
  /// verrouillage, le bouton échouerait sous le doigt.
  bool _trousseauPossible = false;

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    final pile = context.e2ee;
    if (pile == null) {
      if (mounted) setState(() => _charge = false);
      return;
    }
    final dispo = await pile.trousseau.disponible();
    final c = await pile.sauvegarde.lireCoffre();
    if (!mounted) return;
    setState(() {
      _serrures = c.serrures;
      _refusee = c.refusee;
      _trousseauPossible = dispo;
      _charge = false;
    });
  }

  bool _a(String type) => _serrures.any((s) => s.type == type);

  Future<void> _avec(Future<void> Function() travail) async {
    setState(() => _occupe = true);
    try {
      await travail();
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /* ══════════════ ACTIONS ══════════════ */

  /// Ajoute une clé de récupération à une archive déjà ouverte.
  ///
  /// ⚠️ RIEN N'EST RECHIFFRÉ : on ré-enveloppe 32 octets. Une archive de cent
  /// mégaoctets gagne une serrure en quelques millisecondes.
  Future<void> _nouvelleCle() => _avec(() async {
        final cle = await context.e2ee?.sauvegarde.ajouterCleRecuperation();
        if (!mounted) return;
        if (cle == null) {
          showAppSnackBar(
            "La sauvegarde n'est pas ouverte sur cet appareil. "
            "Restaurez-la d'abord avec votre clé de récupération.",
          );
          return;
        }
        await _montrerCle(cle);
        await _relire();
      });

  /// Rouvre une archive que cet appareil n'a jamais ouverte.
  ///
  /// 🔴 LA SEULE SORTIE quand l'archive vient d'un autre appareil. Les douze
  /// mots viennent de l'utilisateur : nous ne les avons jamais eus, et c'est
  /// tout l'intérêt.
  Future<void> _restaurerAvecCle() => _avec(() async {
        final pile = context.e2ee;
        if (pile == null) return;

        final saisie = await _demanderTexte(
          titre: 'Restaurer la sauvegarde',
          explication:
              'Saisissez vos douze mots. Majuscules et espaces en trop ne '
              'posent pas de problème.',
          champ: 'Clé de récupération',
        );
        if (saisie == null || saisie.isEmpty) return;

        final ok = await pile.sauvegarde
            .ouvrirParRecuperation(saisie, pile.coffre);
        if (!mounted) return;
        if (!ok) {
          showAppSnackBar("Ces mots n'ouvrent pas la sauvegarde.");
          return;
        }
        final r = await pile.sauvegarde.restaurer();
        if (!mounted) return;
        showAppSnackBar(
          r.illisibles == 0
              ? '${r.messages.length} message(s) restauré(s).'
              : '${r.messages.length} message(s) restauré(s), '
                  '${r.illisibles} bloc(s) illisible(s).',
        );
        await _relire();
      });

  /// Supprime tout — définitivement.
  ///
  /// ⚠️ ON AVERTIT AVANT, PAS APRÈS. Personne ne peut reconstituer ce qui part
  /// ici, nous pas davantage que l'utilisateur.
  Future<void> _desactiver() => _avec(() async {
        final sur = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Désactiver la sauvegarde ?'),
            content: const Text(
              'Elle sera supprimée définitivement et ne se réactivera pas '
              'toute seule. Ni vous ni nous ne pourrons récupérer ce qui part. '
              'Vos messages continueront de fonctionner, mais ne survivront '
              'plus à un changement d’appareil.',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Désactiver'),
              ),
            ],
          ),
        );
        if (sur != true) return;
        await context.e2ee?.sauvegarde.toutEffacer();
        await _relire();
      });

  /// Pose la serrure du trousseau de cet appareil.
  ///
  /// 🔴 C'EST LA SEULE SERRURE QUE NOTRE SERVEUR NE PEUT PAS OUVRIR : son secret
  /// ne lui est jamais transmis, contrairement au mot de passe qu'il reçoit à
  /// chaque connexion.
  Future<void> _poserTrousseau() => _avec(() async {
        final pile = context.e2ee;
        if (pile == null) return;

        final secret = await pile.trousseau.secret(
          raison: 'Protéger votre sauvegarde avec cet appareil',
        );
        // ⚠️ ANNULER N'EST PAS UNE PANNE : on ne dit rien.
        if (secret == null) return;

        final appareil = '${await pile.coffre.deviceId()}';
        final ok = await pile.sauvegarde.poserTrousseau(secret, appareil);
        if (!mounted) return;
        showAppSnackBar(ok
            ? 'Cet appareil ouvre maintenant votre sauvegarde.'
            : "La sauvegarde n'est pas ouverte sur cet appareil.");
        await _relire();
      });

  /// Ouvre l'archive par le trousseau, sans rien taper.
  Future<void> _ouvrirParTrousseau() => _avec(() async {
        final pile = context.e2ee;
        if (pile == null) return;

        final secret = await pile.trousseau.secret(
          raison: 'Ouvrir votre sauvegarde',
        );
        if (secret == null) return;

        final appareil = '${await pile.coffre.deviceId()}';
        final ok = await pile.sauvegarde
            .ouvrirParTrousseau(secret, appareil, pile.coffre);
        if (!mounted) return;
        if (!ok) {
          showAppSnackBar('Cet appareil n’a pas de serrure sur cette sauvegarde.');
          return;
        }
        final r = await pile.sauvegarde.restaurer();
        if (!mounted) return;
        showAppSnackBar('${r.messages.length} message(s) restauré(s).');
      });

  /* ══════════════ DIALOGUES ══════════════ */

  Future<String?> _demanderTexte({
    required String titre,
    required String explication,
    required String champ,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explication, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: champ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  /// Montre les douze mots, une seule fois.
  ///
  /// ⚠️ L'AVERTISSEMENT VIENT AVANT LES MOTS. Lu après, il arrive une fois les
  /// mots déjà recopiés à la va-vite — trop tard pour changer le soin qu'on y a
  /// mis.
  Future<void> _montrerCle(String cle) {
    final mots = cle.split(' ');
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre clé de récupération'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notez-la maintenant. Elle ne sera plus jamais affichée, et nous '
              'ne pouvons pas la retrouver.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            // ⚠️ NUMÉROTÉS : douze mots se recopient dans le désordre plus
            // souvent qu'on ne le croit, et l'erreur ne se découvre qu'au
            // moment de s'en servir — des mois plus tard.
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (var i = 0; i < mots.length; i++)
                  Text('${i + 1}. ${mots[i]}',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13.5)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: cle)),
            child: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Je l’ai notée'),
          ),
        ],
      ),
    );
  }

  /* ══════════════ AFFICHAGE ══════════════ */

  @override
  Widget build(BuildContext context) {
    final active = _serrures.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde chiffrée')),
      body: _charge
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  active
                      ? 'Vos messages chiffrés sont sauvegardés. Personne '
                          'd’autre que vous ne peut ouvrir cette sauvegarde.'
                      : _refusee
                          ? 'La sauvegarde est désactivée. Vos messages chiffrés '
                              'ne vivent que sur cet appareil : si vous le '
                              'perdez, ils sont perdus avec lui.'
                          : 'Aucune sauvegarde pour l’instant.',
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 18),

                /*
                 * ⚠️ VERT POUR CE QUI EXISTE, GRIS POUR CE QUI MANQUE — jamais
                 * rouge. Une serrure absente n'est pas une panne : c'est un
                 * choix que l'utilisateur n'a pas encore fait.
                 */
                for (final t in const ['motdepasse', 'recuperation', 'trousseau'])
                  ListTile(
                    dense: true,
                    leading: Icon(
                      _a(t) ? Icons.check_circle : Icons.circle_outlined,
                      color: _a(t) ? const Color(0xFF2C6B34) : Colors.grey,
                      size: 20,
                    ),
                    title: Text(switch (t) {
                      'motdepasse' => 'Mot de passe',
                      'recuperation' => 'Clé de récupération',
                      _ => 'Trousseau de l’appareil',
                    }),
                  ),

                const SizedBox(height: 14),
                if (active && !_a('recuperation'))
                  FilledButton(
                    onPressed: _occupe ? null : _nouvelleCle,
                    child: const Text('Créer une clé de récupération'),
                  ),
                if (active) const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _occupe ? null : _restaurerAvecCle,
                  child: const Text('Restaurer avec ma clé de récupération'),
                ),
                if (_trousseauPossible) ...[
                  const SizedBox(height: 8),
                  if (active && !_a('trousseau'))
                    OutlinedButton(
                      onPressed: _occupe ? null : _poserTrousseau,
                      child: const Text('Utiliser cet appareil pour ouvrir'),
                    ),
                  if (_a('trousseau'))
                    OutlinedButton(
                      onPressed: _occupe ? null : _ouvrirParTrousseau,
                      child: const Text('Ouvrir avec cet appareil'),
                    ),
                ],
                if (active) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _occupe ? null : _desactiver,
                    child: const Text(
                      'Désactiver la sauvegarde',
                      style: TextStyle(color: Color(0xFF9B2C2C)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
