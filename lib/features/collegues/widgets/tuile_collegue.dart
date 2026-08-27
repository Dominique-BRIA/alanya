import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../calls/call_controller.dart';
import '../../calls/screens/active_call_screen.dart';
import '../../chat/chat_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../collegues_repository.dart';

/// Un collègue, avec ses deux gestes : appeler, écrire.
///
/// ⚠️ PARTAGÉE PAR LA LISTE D'UN SERVICE ET PAR LA RECHERCHE. Écrire deux
/// tuiles ferait deux fois le même enchaînement d'appel — et c'est exactement
/// là que les comportements divergent : l'un finirait par ouvrir l'écran
/// d'appel et l'autre non, sans que personne ne s'en aperçoive.
class TuileCollegue extends StatefulWidget {
  const TuileCollegue({super.key, required this.collegue});

  final Collegue collegue;

  @override
  State<TuileCollegue> createState() => _TuileCollegueState();
}

class _TuileCollegueState extends State<TuileCollegue> {
  bool _occupe = false;

  /// Ouvre la conversation avec ce collègue.
  ///
  /// ⚠️ `createDirect` est IDEMPOTENT côté serveur : il retrouve la
  /// conversation existante ou la crée. On ne cherche donc pas à savoir
  /// laquelle des deux situations on est — c'est le serveur qui tranche, et
  /// deviner ici créerait des doublons.
  Future<void> _ecrire() async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      final convId = await context
          .read<ChatRepository>()
          .createDirect(widget.collegue.publicNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            convId: convId,
            title: widget.collegue.nom,
            avatarUrl: widget.collegue.avatarUrl,
            otherUserId: widget.collegue.id,
            otherPublicNumber: widget.collegue.publicNumber,
          ),
        ),
      );
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Appelle ce collègue.
  ///
  /// Même enchaînement que depuis la fiche d'un contact : la conversation est
  /// obtenue d'abord — c'est elle qui porte l'appel — puis l'écran d'appel est
  /// ouvert. Sans cette ouverture, l'appel démarre sans que rien ne s'affiche.
  Future<void> _appeler() async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      final convId = await context
          .read<ChatRepository>()
          .createDirect(widget.collegue.publicNumber);
      if (!mounted) return;
      await context
          .read<CallController>()
          .startOutgoing(convId, "AUDIO", widget.collegue.nom);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ActiveCallScreen(),
        ),
      );
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collegue;
    final muted = mutedOf(context, Colors.black54);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarCircle(name: c.nom, avatarUrl: c.avatarUrl, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.nom,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // L'Alanya ID FORMATÉ, comme partout ailleurs dans
                      // l'application : c'est sous cette forme que les gens le
                      // lisent et le recopient.
                      Text(
                        formatAlanyaId(c.publicNumber),
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      // L'AGENCE, juste sous le numéro (demande du user,
                      // 26/08/2026).
                      //
                      // ⚠️ RIEN DU TOUT quand elle manque, et pas un tiret :
                      // un agent sans fonction rattachée n'a pas d'agence, et
                      // le cas est réel en production. Une ligne creuse sous le
                      // numéro se lirait comme une donnée perdue, alors qu'il
                      // n'y a simplement rien à dire.
                      //
                      // Plus petite et plus pâle que le numéro : elle situe la
                      // personne, elle ne sert pas à la joindre — c'est le
                      // numéro qu'on vient chercher ici.
                      if (c.agence != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.business_outlined,
                                size: 12, color: muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                c.agence!,
                                style: TextStyle(fontSize: 12, color: muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // La présence, en pastille sobre plutôt qu'en libellé : elle
                // n'est qu'un indice, et le nom doit rester ce qu'on lit.
                if (c.enLigne)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AlanyaColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _occupe ? null : _appeler,
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(tr(context, 'call')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _occupe ? null : _ecrire,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(tr(context, 'message')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
