import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../account/account_repository.dart';

/// Écran « Historique de connexion » : quand et depuis où le compte a été
/// ouvert.
///
/// Complète l'écran « Appareils connectés », qui montre l'état courant. Ici on
/// montre les événements : c'est ce qui permet de repérer une connexion qu'on
/// ne reconnaît pas, même si l'appareil a depuis disparu de la liste.
class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key});

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  List<LoginAccess>? _acces;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    try {
      final liste = await context.read<AccountRepository>().loginHistory();
      if (!mounted) return;
      setState(() => _acces = liste);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = "Impossible de charger l'historique.\nVérifie ta connexion.";
        _acces = [];
      });
    }
  }

  /// Date lisible : « Aujourd'hui à 14:32 », « Hier à 09:05 », puis la date.
  String _quand(DateTime d) {
    final l = d.toLocal();
    final heure =
        "${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}";
    final aujourdhui = DateTime.now();
    final jour = DateTime(l.year, l.month, l.day);
    final ceJour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    final ecart = ceJour.difference(jour).inDays;

    if (ecart == 0) return "Aujourd'hui à $heure";
    if (ecart == 1) return "Hier à $heure";
    return "Le ${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} à $heure";
  }

  IconData _icone(LoginAccess a) {
    final s = a.osSystem.toLowerCase();
    if (s.contains("android") || s.contains("ios")) {
      return Icons.smartphone_outlined;
    }
    if (s.contains("windows") || s.contains("mac") || s.contains("linux")) {
      return Icons.desktop_windows_outlined;
    }
    return Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    final acces = _acces;

    return Scaffold(
      appBar: backAppBar(context, "Historique de connexion"),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              "Chaque ouverture de session sur ton compte est enregistrée ici. "
              "Si tu vois une connexion que tu ne reconnais pas, change ton mot "
              "de passe et déconnecte l'appareil concerné.",
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: mutedOf(context, Colors.black54),
              ),
            ),
            const SizedBox(height: 20),
            if (acces == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_erreur != null)
              _message(_erreur!, dangerOf(context))
            else if (acces.isEmpty)
              _message(
                "Aucune connexion enregistrée pour le moment.",
                mutedOf(context, Colors.black54),
              )
            else
              ...List.generate(acces.length, (i) => _tuile(acces[i], i == 0)),
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

  Widget _tuile(LoginAccess a, bool derniere) {
    // Détail secondaire : appareil et IP quand ils sont connus. Une valeur
    // « INDEFINI » n'apporte rien à l'utilisateur, on l'omet.
    final details = <String>[
      if (a.deviceConnu) a.device,
      if (a.systemeConnu) a.osSystem,
      if (a.ipConnue) a.ipAdress,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: themed(context, light: Colors.white, dark: surfacesOf(context).surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: themed(context,
              light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
          width: 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: themed(context,
                light: AlanyaColors.grey100, dark: surfacesOf(context).surfaceHaute),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            _icone(a),
            size: 20,
            color: mutedOf(context, AlanyaColors.grey500),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                _quand(a.dateLogin),
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            // La connexion la plus récente est celle de la session en cours,
            // dans l'immense majorité des cas.
            if (derniere) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentOf(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "La plus récente",
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        subtitle: details.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  details.join(" · "),
                  style: TextStyle(
                      fontSize: 12, color: mutedOf(context, Colors.black54)),
                ),
              ),
      ),
    );
  }
}
