import 'package:flutter/material.dart';

import '../../../core/geo_service.dart';
import '../../../theme/alanya_theme.dart';

/// Écran de divulgation du suivi de position.
///
/// ⚠️ CET ÉCRAN N'EST PAS UNE POLITESSE, C'EST UNE OBLIGATION. L'application
/// part en distribution PUBLIQUE sur le Play Store, et la règle de Google sur
/// `ACCESS_BACKGROUND_LOCATION` exige une « divulgation bien visible » **dans
/// l'application, AVANT toute demande de permission** — la boîte de dialogue du
/// système ne suffit pas. Elle doit dire ce qui est collecté, pourquoi, que la
/// collecte continue **application fermée**, et laisser un vrai choix.
///
/// ⚠️ UN REFUS NE BLOQUE RIEN. La règle interdit d'exiger la localisation
/// d'arrière-plan pour un usage principal qui n'en dépend pas : Alanya Work est
/// une messagerie, la bloquer sur un refus serait un motif de rejet direct. Le
/// besoin de l'entreprise passe par la visibilité du refus, pas par la
/// contrainte.
///
/// Affiché UNE SEULE FOIS, et seulement aux comptes que le serveur déclare
/// concernés (`suiviPosition`). Un particulier ne le verra jamais.
class GeoDisclosureScreen extends StatefulWidget {
  const GeoDisclosureScreen({super.key, required this.userId});

  /// ⚠️ Le consentement appartient à une PERSONNE, pas au téléphone. Il était
  /// enregistré globalement : sur un appareil partagé, un compte héritait du
  /// « oui » d'un autre et se retrouvait suivi sans avoir été consulté.
  final String userId;

  @override
  State<GeoDisclosureScreen> createState() => _GeoDisclosureScreenState();
}

class _GeoDisclosureScreenState extends State<GeoDisclosureScreen> {
  bool _enCours = false;

  Future<void> _repondre(bool accepte) async {
    setState(() => _enCours = true);
    await GeoService.instance.enregistreConsentement(widget.userId, accepte);
    // La permission n'est demandée QU'APRÈS un accord explicite : c'est tout
    // l'objet de cet écran, et l'ordre inverse serait précisément ce que la
    // règle interdit.
    if (accepte) await GeoService.instance.demandePermissions();
    if (!mounted) return;
    Navigator.of(context).pop(accepte);
  }

  @override
  Widget build(BuildContext context) {
    final muted = mutedOf(context, Colors.black54);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: accentOf(context),
                  child: const Icon(Icons.my_location,
                      size: 38, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Suivi de votre position",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                "Votre compte est rattaché à une entreprise. Dans le cadre du "
                "suivi de son activité, Alanya Work enregistre votre position.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: muted),
              ),
              const SizedBox(height: 24),

              _point(
                context,
                Icons.schedule,
                "Toutes les 5 minutes",
                "Un relevé est enregistré. Si vous n'avez pas changé d'endroit, "
                    "aucune nouvelle ligne n'est créée : seule la durée de votre "
                    "présence est prolongée.",
              ),
              // Mention EXPLICITE de l'arrière-plan : c'est celle que Google
              // vérifie, et celle qui manque le plus souvent.
              _point(
                context,
                Icons.phonelink_lock,
                "Y compris application fermée",
                "La collecte continue lorsque l'application est en arrière-plan "
                    "ou fermée. Une notification permanente vous le rappelle "
                    "tant qu'elle est active.",
              ),
              _point(
                context,
                Icons.business_center_outlined,
                "Visible par votre entreprise",
                "Ces relevés sont destinés à l'entreprise à laquelle votre "
                    "compte est rattaché. Ils ne sont partagés avec personne "
                    "d'autre.",
              ),
              _point(
                context,
                Icons.do_not_disturb_on_outlined,
                "Vous pouvez refuser",
                "L'application reste entièrement utilisable : messages, appels "
                    "et réunions fonctionnent à l'identique. Votre entreprise "
                    "sera informée que le suivi n'est pas actif.",
              ),

              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _enCours ? null : () => _repondre(true),
                  child: Text(_enCours ? "Un instant…" : "J'accepte le suivi"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: _enCours ? null : () => _repondre(false),
                  child: const Text("Refuser"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(
      BuildContext context, IconData icone, String titre, String detail) {
    final muted = mutedOf(context, Colors.black54);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: accentOf(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(detail,
                    style: TextStyle(fontSize: 13, color: muted, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
