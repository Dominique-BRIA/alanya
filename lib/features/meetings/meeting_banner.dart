import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:alanya/core/app_snackbar.dart';
import 'package:alanya/core/push_service.dart';
import 'package:alanya/theme/alanya_theme.dart';
import 'meeting_controller.dart';
import 'screens/meeting_room_screen.dart';
import '../../l10n/app_localizations.dart';

/// Bandeau global « réunion en cours » affiché par-dessus toutes les pages
/// quand une réunion est active mais que l'écran de salle n'est pas affiché
/// (l'utilisateur l'a réduite pour naviguer dans l'app). Toucher le bandeau
/// rouvre la salle.
///
/// À utiliser dans `MaterialApp.builder`, à l'intérieur d'un Stack (aux côtés
/// du `CallBanner`).
class MeetingBanner extends StatefulWidget {
  const MeetingBanner({super.key});

  @override
  State<MeetingBanner> createState() => _MeetingBannerState();
}

class _MeetingBannerState extends State<MeetingBanner> {
  Timer? _ticker;
  StreamSubscription<MeetingRefus>? _refusSub;

  @override
  void initState() {
    super.initState();
    // Rafraîchit le minuteur chaque seconde tant que le bandeau vit.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Une seule souscription, même si les dépendances changent plusieurs fois.
    _refusSub ??= context.read<MeetingController>().refus.listen(_onRefus);
  }

  /// Le serveur a refusé l'entrée ALORS QUE LA SALLE ÉTAIT RÉDUITE.
  ///
  /// POURQUOI ICI ET PAS SEULEMENT DANS LA SALLE. Le refus n'arrive pas
  /// uniquement à l'entrée : après une coupure réseau, le contrôleur se
  /// réinscrit dans la salle, et la place a pu être prise entre-temps. On peut
  /// donc être expulsé en lisant ses messages ailleurs dans l'application —
  /// l'écran de salle n'est alors pas monté, personne n'écoute, et le bandeau
  /// vert disparaîtrait sans un mot.
  ///
  /// Ce bandeau-ci est la SEULE surface toujours vivante : son `State` survit
  /// même quand son `build` ne rend rien.
  ///
  /// [MeetingRefus.salleAffichee] évite le doublon : quand la salle est ouverte,
  /// c'est elle qui parle, avec un vrai dialogue et le message complet.
  void _onRefus(MeetingRefus refus) {
    if (refus.salleAffichee) return;
    // Composé ici et non dans le contrôleur : la phrase du client doit passer
    // par `tr()`, et seul l'écran a le contexte. Le message du serveur, lui,
    // reste tel quel — c'est lui qui sait dire pourquoi l'entrée a été refusée.
    showAppSnackBar(refus.estSallePleine && refus.plafond != null
        ? tr(context, 'meet_room_full_short', {'plafond': '${refus.plafond}'})
        : refus.messageServeur);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refusSub?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime? since) {
    if (since == null) return "";
    final d = DateTime.now().difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    final base =
        "${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
    return d.inHours > 0 ? "${two(d.inHours)}:$base" : base;
  }

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<MeetingController>();
    final visible = mc.isActive && !mc.roomVisible;
    if (!visible) return const SizedBox.shrink();

    final elapsed = _elapsed(mc.connectedSince);
    final label = elapsed.isNotEmpty
        ? tr(context, 'meet_ongoing_banner', {'temps': elapsed})
        : tr(context, 'meet_ongoing_dots');

    // Combien de mains sont levées, la mienne comprise. Le bandeau est la SEULE
    // surface visible quand la salle est réduite : sans ce compte, une demande
    // de parole passerait inaperçue tant qu'on lit ses messages ailleurs. Une
    // pastille et un chiffre, pas les noms — le bandeau ne fait qu'appeler, la
    // salle dit qui.
    final mains = mc.peerIds.where(mc.isHandRaised).length +
        (mc.myHandRaised ? 1 : 0);

    // Décalé sous le bandeau d'appel si jamais les deux coexistent (peu
    // probable, les réunions ne verrouillent pas l'état occupé).
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                final id = mc.activeMeetingId;
                if (id == null) return;
                PushService.navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => MeetingRoomScreen(
                      meetingId: id,
                      objet: mc.activeObjet ?? tr(context, 'meet_page_title'),
                      isVideo: mc.activeIsVideo,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AlanyaColors.forest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black38),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (mains > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: AlanyaColors.gold,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.back_hand,
                                color: Colors.white, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              "$mains",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(tr(context, 'meet_return'),
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
