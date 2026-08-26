import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../calls/call_controller.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../chat/chat_repository.dart';
import '../entreprises_repository.dart';

/// Un standard, avec ses services et de quoi l'appeler.
///
/// ⚠️ EXTRAITE DE LA FICHE D'ENTREPRISE le 26/08/2026, quand les centres sont
/// passés derrière un écran par type. Elle est restée un widget à part plutôt
/// que d'être recopiée : c'est elle qui porte l'enchaînement d'appel, et deux
/// copies de cet enchaînement finiraient par diverger — l'une ouvrant l'écran
/// d'appel et l'autre non, sans que personne ne s'en aperçoive.
class CarteCentre extends StatefulWidget {
  const CarteCentre({super.key, required this.centre});

  final CentreEntreprise centre;

  @override
  State<CarteCentre> createState() => _CarteCentreState();
}

class _CarteCentreState extends State<CarteCentre> {
  bool _occupe = false;

  /// Appelle le standard.
  ///
  /// Même enchaînement que partout ailleurs : la conversation directe est
  /// obtenue d'abord — c'est elle qui porte l'appel — puis l'écran d'appel est
  /// ouvert. C'est cet écran qui affiche le pavé à touches, dont l'appelant
  /// aura besoin dès que le menu se lance.
  Future<void> _appeler() async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      final convId = await context
          .read<ChatRepository>()
          .createDirect(widget.centre.alanyaId);
      if (!mounted) return;
      await context
          .read<CallController>()
          .startOutgoing(convId, "AUDIO", widget.centre.nom);
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
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centre = widget.centre;
    final muted = mutedOf(context, Colors.black54);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
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
                      // L'Alanya ID formaté : c'est ce qu'on compose, et c'est
                      // sous cette forme qu'il se lit partout ailleurs.
                      Text(formatAlanyaId(centre.alanyaId),
                          style: TextStyle(color: muted, fontSize: 13)),
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
                onPressed: _occupe ? null : _appeler,
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
