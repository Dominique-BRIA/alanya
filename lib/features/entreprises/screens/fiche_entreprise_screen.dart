import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../calls/call_controller.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../chat/chat_repository.dart';
import '../entreprises_repository.dart';

/// La fiche d'une entreprise : ses standards, et de quoi les appeler.
class FicheEntrepriseScreen extends StatefulWidget {
  const FicheEntrepriseScreen({
    super.key,
    required this.idEntreprise,
    required this.titre,
  });

  final int idEntreprise;

  /// Le nom déjà connu de l'écran précédent — évite un titre vide pendant le
  /// chargement.
  final String titre;

  @override
  State<FicheEntrepriseScreen> createState() => _FicheEntrepriseScreenState();
}

class _FicheEntrepriseScreenState extends State<FicheEntrepriseScreen> {
  FicheEntreprise? _fiche;
  bool _erreur = false;
  String? _appelEnCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _erreur = false);
    try {
      final f = await context
          .read<EntreprisesRepository>()
          .fiche(widget.idEntreprise);
      if (!mounted) return;
      setState(() => _fiche = f);
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  /// Appelle un standard.
  ///
  /// Même enchaînement que partout ailleurs : la conversation directe est
  /// obtenue d'abord — c'est elle qui porte l'appel — puis l'écran d'appel est
  /// ouvert. C'est cet écran qui affiche le pavé à touches, dont l'appelant
  /// aura besoin dès que le menu se lance.
  Future<void> _appeler(CentreEntreprise centre) async {
    if (_appelEnCours != null) return;
    setState(() => _appelEnCours = centre.alanyaId);
    try {
      final convId =
          await context.read<ChatRepository>().createDirect(centre.alanyaId);
      if (!mounted) return;
      await context
          .read<CallController>()
          .startOutgoing(convId, "AUDIO", centre.nom);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(),
        ),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _appelEnCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final fiche = _fiche;

    return Scaffold(
      appBar: backAppBar(context, fiche?.entreprise.libelle ?? widget.titre),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _charger,
          child: _corps(fiche, muted),
        ),
      ),
    );
  }

  Widget _corps(FicheEntreprise? fiche, Color muted) {
    if (_erreur) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(tr(context, 'server_unreachable'),
                textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
                onPressed: _charger, child: Text(tr(context, 'retry'))),
          ),
        ],
      );
    }
    if (fiche == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final e = fiche.entreprise;
    // Pays et ville sur une ligne, en n'affichant que ce qui existe : la
    // moitié des entreprises n'a ni l'un ni l'autre en base.
    final lieu = [e.ville, e.pays].whereType<String>().join(", ");

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (e.description != null || lieu.isNotEmpty || e.adresse != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.description != null)
                  Text(e.description!, style: TextStyle(color: muted)),
                if (e.adresse != null) ...[
                  const SizedBox(height: 6),
                  Text(e.adresse!, style: TextStyle(color: muted, fontSize: 13)),
                ],
                if (lieu.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(lieu, style: TextStyle(color: muted, fontSize: 13)),
                ],
              ],
            ),
          ),

        if (fiche.centres.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
            child: Text(tr(context, 'company_no_center'),
                textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ),

        for (final c in fiche.centres) _carteCentre(c, muted),
      ],
    );
  }

  Widget _carteCentre(CentreEntreprise centre, Color muted) {
    final occupe = _appelEnCours == centre.alanyaId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // L'icône distingue un standard humain d'un serveur vocal :
                // on n'attend pas la même chose des deux, et le savoir AVANT
                // d'appeler évite de patienter pour une machine.
                Icon(
                  centre.estVocal ? Icons.graphic_eq : Icons.headset_mic_outlined,
                  color: accentOf(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(centre.nom,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        "${tr(context, centre.estVocal ? 'company_center_vocal' : 'company_center_call')} · ${formatAlanyaId(centre.alanyaId)}",
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (centre.services.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr(context, 'company_services'),
                  style: TextStyle(
                      color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final s in centre.services) _ligneService(s, muted),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: occupe ? null : () => _appeler(centre),
                icon: const Icon(Icons.call, size: 18),
                label: Text(tr(context, 'call')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneService(ServiceTouche s, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La TOUCHE en pastille : c'est le chiffre que l'appelant devra
          // composer, et il reste lisible même quand le service n'a pas de nom.
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentOf(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text("${s.touche}",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentOf(context))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Le serveur rend `null` quand le service n'est pas nommé : c'est
              // ICI qu'on le dit, dans la langue de l'utilisateur.
              s.nom ?? tr(context, 'company_service_unnamed'),
              style: TextStyle(
                fontSize: 14,
                // Le nom manquant est mis en retrait : il ne doit pas se lire
                // comme un intitulé de service.
                color: s.nom == null ? muted : null,
                fontStyle: s.nom == null ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
