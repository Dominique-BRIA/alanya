import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/realtime_client.dart';

import '../../../core/device_registry.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';

/// Écran « Appareils connectés » : les sessions ouvertes sur le compte, avec
/// déconnexion à distance.
///
/// L'appareil courant est marqué et non déconnectable depuis cet écran — s'en
/// déconnecter soi-même est le rôle du bouton « Se déconnecter » des réglages.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<AppareilInfo>? _appareils;
  String? _erreur;
  String? _idCourant;
  int? _enCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    try {
      final id = await DeviceRegistry.instance.deviceId();
      final liste = await DeviceRegistry.instance.list();
      if (!mounted) return;
      setState(() {
        _idCourant = id;
        _appareils = liste;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = "Impossible de charger tes appareils.\nVérifie ta connexion.";
        _appareils = [];
      });
    }
  }

  Future<void> _deconnecter(AppareilInfo a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Déconnecter cet appareil ?"),
        content: Text(
          "${a.libelle} n'aura plus accès à ton compte. "
          "Il faudra s'y reconnecter avec ton mot de passe.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Déconnecter", style: TextStyle(color: dangerOf(context))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enCours = a.appareilId);
    try {
      await DeviceRegistry.instance.disconnect(a.appareilId);
      if (!mounted) return;
      // Coupe l'accès sans attendre l'expiration du jeton : l'appareil visé
      // reçoit l'annonce et se déconnecte de lui-même.
      final id = a.cookiesWebId;
      if (id != null) context.read<RealtimeClient>().sendSessionRevoked(id);
      setState(() {
        _appareils =
            (_appareils ?? []).where((x) => x.appareilId != a.appareilId).toList();
        _enCours = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${a.libelle} a été déconnecté.")),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _enCours = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Déconnexion impossible. Réessaie.")),
      );
    }
  }

  /// « À l'instant », « Il y a 3 h », puis la date complète.
  String _derniereActivite(DateTime? d) {
    if (d == null) return "Jamais connecté";
    final minutes = DateTime.now().difference(d).inMinutes;
    if (minutes < 2) return "À l'instant";
    if (minutes < 60) return "Il y a $minutes min";
    if (minutes < 24 * 60) return "Il y a ${minutes ~/ 60} h";
    if (minutes < 7 * 24 * 60) return "Il y a ${minutes ~/ 1440} j";
    return "Le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
  }

  IconData _icone(int type) {
    switch (type) {
      case 1:
      case 2:
        return Icons.smartphone_outlined;
      case 3:
        return Icons.desktop_windows_outlined;
      default:
        return Icons.language;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appareils = _appareils;

    return Scaffold(
      appBar: backAppBar(context, "Appareils connectés"),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              "Ton compte Alanya est ouvert sur les appareils ci-dessous. "
              "Si tu n'en reconnais pas un, déconnecte-le : il devra se "
              "reconnecter avec ton mot de passe.",
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: mutedOf(context, Colors.black54),
              ),
            ),
            const SizedBox(height: 20),

            if (appareils == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_erreur != null)
              _message(_erreur!, dangerOf(context))
            else if (appareils.isEmpty)
              _message(
                "Aucun appareil enregistré pour le moment.",
                mutedOf(context, Colors.black54),
              )
            else
              ...appareils.map(_tuile),
          ],
        ),
      ),
    );
  }

  Widget _message(String texte, Color couleur) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: couleur),
        ),
      );

  Widget _tuile(AppareilInfo a) {
    final courant = a.cookiesWebId != null && a.cookiesWebId == _idCourant;
    final occupe = _enCours == a.appareilId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: courant
            ? accentOf(context).withValues(alpha: 0.08)
            : themed(context, light: Colors.white, dark: surfacesOf(context).surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: courant
              ? accentOf(context).withValues(alpha: 0.4)
              : themed(context,
                  light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
          width: 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: themed(context,
                light: AlanyaColors.grey100, dark: surfacesOf(context).surfaceHaute),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _icone(a.typeDevice),
            size: 21,
            color: courant
                ? accentOf(context)
                : mutedOf(context, AlanyaColors.grey500),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                a.libelle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              ),
            ),
            if (courant) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentOf(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Cet appareil",
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            [
              if (a.system != null && a.system!.isNotEmpty) a.system!,
              _derniereActivite(a.lastLogin),
            ].join(" · "),
            style: TextStyle(
                fontSize: 12, color: mutedOf(context, Colors.black54)),
          ),
        ),
        // L'appareil courant n'est pas déconnectable ici : ce serait une
        // déconnexion déguisée, avec un libellé qui ne le dit pas.
        trailing: courant
            ? null
            : occupe
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: "Déconnecter",
                    icon: Icon(Icons.logout, size: 20, color: dangerOf(context)),
                    onPressed: () => _deconnecter(a),
                  ),
      ),
    );
  }
}
