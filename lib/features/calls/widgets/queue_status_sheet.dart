import 'package:flutter/material.dart';
import '../../../core/authed_api.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';

/// Tiroir « Liste d'attente » — ouvert depuis l'écran d'appel d'un agent,
/// pour le centre qui a routé l'appel EN COURS (voir `CallController.
/// activeIvrFromId`). Montre qui attend MAINTENANT et qui a abandonné
/// récemment, sur ce même centre.
///
/// Lecture seule : rappeler un abandonné se fait depuis l'écran « Clients
/// abandonnés » (menu ⋮), pas d'ici — en plein appel n'est pas le moment.
class QueueStatusSheet extends StatefulWidget {
  final String centerAlanyaID;
  final AuthedApi api;

  const QueueStatusSheet({
    super.key,
    required this.centerAlanyaID,
    required this.api,
  });

  static Future<void> show(
    BuildContext context, {
    required String centerAlanyaID,
    required AuthedApi api,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QueueStatusSheet(centerAlanyaID: centerAlanyaID, api: api),
    );
  }

  @override
  State<QueueStatusSheet> createState() => _QueueStatusSheetState();
}

class _QueueStatusSheetState extends State<QueueStatusSheet> {
  bool _chargement = true;
  String? _erreur;
  List<Map<String, dynamic>> _enAttente = [];
  List<Map<String, dynamic>> _abandonnes = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final results = await Future.wait([
        widget.api.get('/api/queue/live?centerAlanyaID=${widget.centerAlanyaID}'),
        widget.api.get(
            '/api/queue/history?centerAlanyaID=${widget.centerAlanyaID}&excludeServed=1&limit=30'),
      ]);
      if (!mounted) return;
      setState(() {
        _enAttente = List<Map<String, dynamic>>.from(results[0]['live'] as List? ?? []);
        _abandonnes = List<Map<String, dynamic>>.from(results[1]['history'] as List? ?? []);
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = "Impossible de charger la file d'attente";
        _chargement = false;
      });
    }
  }

  String _duree(int secondes) {
    final m = secondes ~/ 60;
    final s = secondes % 60;
    return m > 0 ? "$m min ${s}s" : "${s}s";
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1F2C34),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 20),
                    child: Text(
                      "Liste d'attente",
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _chargement ? null : _charger,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _chargement
                    ? const Center(child: CircularProgressIndicator())
                    : _erreur != null
                        ? Center(
                            child: Text(_erreur!, style: const TextStyle(color: Colors.white70)))
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              _sectionTitre(
                                  "En attente maintenant (${_enAttente.length})"),
                              if (_enAttente.isEmpty) _videMessage("Personne n'attend."),
                              for (final l in _enAttente)
                                _ligneAttente(l),
                              const SizedBox(height: 20),
                              _sectionTitre("Abandons récents (${_abandonnes.length})"),
                              if (_abandonnes.isEmpty)
                                _videMessage("Aucun abandon récent."),
                              for (final l in _abandonnes) _ligneAbandon(l),
                              const SizedBox(height: 24),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitre(String texte) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          texte,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54),
        ),
      );

  Widget _videMessage(String texte) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texte, style: const TextStyle(color: Colors.white38, fontSize: 13)),
      );

  Widget _ligneAttente(Map<String, dynamic> l) {
    final nom = l['customerName'] as String? ?? "Client";
    final rang = l['rang'];
    final service = l['serviceName'] as String?;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AvatarCircle(name: nom, avatarUrl: l['customerAvatarUrl'] as String?, radius: 20),
      title: Text(nom, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        service != null ? "$service · rang $rang" : "rang $rang",
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.hourglass_top, color: AlanyaColors.gold, size: 18),
    );
  }

  Widget _ligneAbandon(Map<String, dynamic> l) {
    final nom = l['customerName'] as String? ?? "Client";
    final statut = l['statut'] as String? ?? "ABANDON";
    final attente = (l['attenteDureeSec'] as num?)?.toInt() ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AvatarCircle(name: nom, avatarUrl: l['customerAvatarUrl'] as String?, radius: 20),
      title: Text(nom, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        "${statut == 'TIMEOUT' ? 'Expiré' : 'Abandonné'} après ${_duree(attente)}",
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.call_end, color: Colors.redAccent, size: 18),
    );
  }
}
