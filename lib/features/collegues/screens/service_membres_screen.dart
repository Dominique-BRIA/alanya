import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../collegues_repository.dart';
import '../widgets/tuile_collegue.dart';

/// Les collègues d'un service.
class ServiceMembresScreen extends StatefulWidget {
  const ServiceMembresScreen({super.key, required this.service});

  final String service;

  @override
  State<ServiceMembresScreen> createState() => _ServiceMembresScreenState();
}

class _ServiceMembresScreenState extends State<ServiceMembresScreen> {
  final _filtreCtrl = TextEditingController();
  List<Collegue>? _membres;
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _filtreCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _erreur = false);
    try {
      final liste =
          await context.read<ColleguesRepository>().membres(widget.service);
      if (!mounted) return;
      setState(() => _membres = liste);
    } on ApiException {
      if (mounted) setState(() => _erreur = true);
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  /// Filtre LOCAL, sur la liste déjà chargée.
  ///
  /// ⚠️ À ne pas confondre avec la recherche de l'écran précédent, qui interroge
  /// le serveur et traverse TOUS les services. Ici on affine ce qu'on voit ;
  /// là-bas on cherche quelqu'un dont on ignore le service.
  List<Collegue> get _visibles {
    final tous = _membres ?? const <Collegue>[];
    final q = _filtreCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return tous;
    return tous
        .where((c) =>
            c.nom.toLowerCase().contains(q) || c.publicNumber.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    final membres = _membres;

    return Scaffold(
      appBar: backAppBar(context, widget.service),
      body: SafeArea(
        child: Column(
          children: [
            // Le filtre n'apparaît qu'à partir d'une poignée de collègues :
            // au-dessous, il occupe une place pour rien — la liste tient à
            // l'écran et se parcourt à l'œil.
            if (membres != null && membres.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  controller: _filtreCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: tr(context, 'colleagues_filter_hint'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _charger,
                child: _corps(membres, muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corps(List<Collegue>? membres, Color muted) {
    if (_erreur) {
      return _message(tr(context, 'server_unreachable'), muted, avecReessai: true);
    }
    if (membres == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final visibles = _visibles;
    if (visibles.isEmpty) {
      // Deux vides différents, deux messages différents : une liste vide de
      // naissance n'est pas un filtre qui ne trouve rien, et dire « aucun
      // résultat » à qui n'a rien tapé laisse croire à une panne.
      return _message(
        _filtreCtrl.text.trim().isEmpty
            ? tr(context, 'colleagues_service_empty')
            : tr(context, 'colleagues_no_match'),
        muted,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: visibles.length,
      itemBuilder: (_, i) => TuileCollegue(collegue: visibles[i]),
    );
  }

  Widget _message(String texte, Color muted, {bool avecReessai = false}) {
    // `ListView` et non `Center` : le message doit rester tirable pour
    // rafraîchir, sinon un écran d'erreur devient un cul-de-sac.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(texte,
              textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ),
        if (avecReessai) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _charger,
              child: Text(tr(context, 'retry')),
            ),
          ),
        ],
      ],
    );
  }
}
