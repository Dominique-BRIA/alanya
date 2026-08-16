import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../call_controller.dart';
import '../calls_repository.dart';
import '../message_erreur_appel.dart';
import 'active_call_screen.dart';

/// « Clients abandonnés » — menu ⋮ de l'accueil (demande user 15/08/2026).
///
/// Réservé aux agents/centres : `GET /api/queue/history` répond 403 à tout
/// autre compte, affiché ici comme un message clair plutôt qu'une liste
/// vide — pas besoin de savoir « suis-je agent » avant d'ouvrir l'écran.
class AbandonedClientsScreen extends StatefulWidget {
  const AbandonedClientsScreen({super.key});

  @override
  State<AbandonedClientsScreen> createState() => _AbandonedClientsScreenState();
}

class _AbandonedClientsScreenState extends State<AbandonedClientsScreen> {
  bool _chargement = true;
  String? _erreur;
  List<Map<String, dynamic>> _clients = [];
  String? _rappelEnCours;

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
      final clients = await context.read<CallsRepository>().abandonedClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      final reserveAuxAgents = e is ApiException && e.statusCode == 403;
      setState(() {
        _erreur = reserveAuxAgents
            ? "Réservé aux agents d'un centre d'appels."
            : "Impossible de charger la liste.";
        _chargement = false;
      });
    }
  }

  String _duree(int secondes) {
    final m = secondes ~/ 60;
    final s = secondes % 60;
    return m > 0 ? "$m min ${s}s" : "${s}s";
  }

  Future<void> _rappeler(Map<String, dynamic> c) async {
    final centerAlanyaID = c["centerId"] as String?;
    final customerId = c["customerId"] as String?;
    final nom = c["customerName"] as String? ?? "Client";
    if (centerAlanyaID == null || customerId == null) return;

    setState(() => _rappelEnCours = customerId);
    try {
      final cc = context.read<CallController>();
      await cc.startCallback(centerAlanyaID, customerId, nom);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ActiveCallScreen()),
      );
      // Au retour de l'appel : si le client a décroché, le serveur l'a passé
      // en RECONTACTER et il ne fait plus partie de la liste. Sans ce
      // rechargement, l'agent le verrait encore et le rappellerait.
      if (mounted) await _charger();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageErreurAppel(e))),
      );
    } finally {
      if (mounted) setState(() => _rappelEnCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Clients abandonnés"),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _erreur!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : _clients.isEmpty
                  ? const Center(
                      child: Text("Aucun client abandonné pour l'instant.",
                          style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _charger,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _clients.length,
                        itemBuilder: (context, i) {
                          final c = _clients[i];
                          final nom = c["customerName"] as String? ?? "Client";
                          final statut = c["statut"] as String? ?? "ABANDON";
                          final attente = (c["attenteDureeSec"] as num?)?.toInt() ?? 0;
                          final centreName = c["companyName"] as String?;
                          final serviceName = c["serviceName"] as String?;
                          final enCours = _rappelEnCours == c["customerId"];
                          return ListTile(
                            leading: AvatarCircle(
                                name: nom, avatarUrl: c["customerAvatarUrl"] as String?),
                            title: Text(nom),
                            subtitle: Text(
                              [
                                statut == "TIMEOUT" ? "Expiré" : "Abandonné",
                                "après ${_duree(attente)}",
                                if (serviceName != null) serviceName,
                                if (centreName != null) centreName,
                              ].join(" · "),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: enCours
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : IconButton(
                                    icon: const Icon(Icons.call, color: AlanyaColors.forest),
                                    tooltip: "Rappeler",
                                    onPressed: _rappelEnCours != null ? null : () => _rappeler(c),
                                  ),
                          );
                        },
                      ),
                    ),
    );
  }
}
