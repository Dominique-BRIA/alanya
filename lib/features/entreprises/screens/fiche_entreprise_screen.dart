import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../entreprises_repository.dart';
import 'centres_type_screen.dart';

/// La fiche d'une entreprise : ce qu'elle est, puis par où la joindre.
///
/// 🔴 LES CENTRES SONT RANGÉS DERRIÈRE DEUX ENTRÉES — centres d'appel et centre
/// vocal — au lieu d'être listés d'un bloc (demande du user, 26/08/2026).
///
/// Ce n'est pas qu'un rangement : les deux ne se ressemblent pas. L'un met en
/// relation avec une personne, l'autre lit un menu enregistré. Les mélanger
/// obligeait l'appelant à deviner lequel décrocherait, alors que l'écran de
/// chaque type peut désormais l'expliquer avant qu'il compose.
///
/// ⚠️ TOUT EST CHARGÉ EN UNE FOIS ici. Les deux écrans suivants ne refont
/// aucune requête : ils reçoivent les centres déjà triés. Redemander par type
/// coûterait un aller-retour pour des données qu'on tient déjà.
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

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _erreur = false);
    try {
      final f =
          await context.read<EntreprisesRepository>().fiche(widget.idEntreprise);
      if (!mounted) return;
      setState(() => _fiche = f);
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  void _ouvrirType(bool vocal, List<CentreEntreprise> centres) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CentresTypeScreen(vocal: vocal, centres: centres),
      ),
    );
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
    // Ville et pays sur une ligne, en n'affichant que ce qui existe : la moitié
    // des entreprises n'a ni l'un ni l'autre en base.
    final lieu = [e.ville, e.pays].whereType<String>().join(", ");

    final appels = fiche.centres.where((c) => !c.estVocal).toList();
    final vocaux = fiche.centres.where((c) => c.estVocal).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (e.description != null || lieu.isNotEmpty || e.adresse != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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

        /*
         * LES DEUX ENTRÉES, TOUJOURS PRÉSENTES — même à zéro centre.
         *
         * L'écran suivant garde alors sa description et dit que ce type n'est
         * pas encore proposé (demande du user). Masquer l'entrée aurait laissé
         * croire que l'entreprise n'a QUE des centres d'appel, alors que la
         * vérité est « elle n'a pas encore de serveur vocal » — et aurait privé
         * l'utilisateur d'une explication qui vaut par elle-même.
         */
        _entree(
          vocal: false,
          nombre: appels.length,
          centres: appels,
          muted: muted,
        ),
        _entree(
          vocal: true,
          nombre: vocaux.length,
          centres: vocaux,
          muted: muted,
        ),
      ],
    );
  }

  Widget _entree({
    required bool vocal,
    required int nombre,
    required List<CentreEntreprise> centres,
    required Color muted,
  }) {
    // Titre au singulier ou au pluriel selon le compte. Zéro prend le
    // singulier, comme « aucun centre d'appel ».
    final titre = tr(
      context,
      vocal
          ? (nombre > 1 ? 'company_vocal_centers' : 'company_vocal_center')
          : (nombre > 1 ? 'company_call_centers' : 'company_call_center'),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accentOf(context).withValues(alpha: 0.15),
          child: Icon(
            vocal ? Icons.graphic_eq : Icons.headset_mic_outlined,
            color: accentOf(context),
          ),
        ),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
        // Une phrase courte, pour choisir sans avoir à ouvrir. L'explication
        // complète est en tête de l'écran suivant.
        subtitle: Text(
          tr(context, vocal ? 'company_vocal_center_short' : 'company_call_center_short'),
          style: TextStyle(color: muted, fontSize: 13),
        ),
        // Le COMPTE avant le chevron : l'appelant sait ce qu'il y a derrière
        // avant de taper, y compris qu'il n'y a rien.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentOf(context).withValues(alpha: nombre == 0 ? 0.06 : 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "$nombre",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: nombre == 0 ? muted : accentOf(context),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _ouvrirType(vocal, centres),
      ),
    );
  }
}
