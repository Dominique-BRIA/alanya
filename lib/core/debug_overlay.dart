import 'dart:async';
import 'package:flutter/material.dart';

/// Affiche les traces d'appel par-dessus l'application.
///
/// Laissé à `false` : c'est un outil de diagnostic, pas une fonctionnalité.
/// Le repasser à `true` rebranche l'overlay sans rien toucher d'autre — il a
/// permis d'identifier, en une seule capture d'écran, une course que plusieurs
/// correctifs raisonnés n'avaient pas su trouver. Les traces continuent de
/// partir dans le journal système (`adb logcat`), où elles ne coûtent rien.
/// ✅ REPASSÉ À `false` LE 12/08/2026 : la cause est trouvée. Allumé quelques
/// heures pour l'invite vocale du standard restée muette, le bandeau a montré en
/// UNE capture ce que trois hypothèses raisonnées avaient manqué — la lecture
/// démarrait sans erreur, le son sortait simplement par l'écouteur. Deuxième
/// fois que cet outil tranche là où le raisonnement s'égarait.
///
/// ⚠️ Les traces elles-mêmes RESTENT en place, et c'est délibéré : `traceAppel`
/// continue d'écrire dans le journal système, où elle ne coûte rien et où `adb
/// logcat` la retrouvera. Seul l'affichage est coupé.
/// 🔴 RALLUMÉ LE 24/08/2026, TROISIÈME FOIS — chip vert « appel en cours » qui
/// n'apparaît pas. Même raison que les deux précédentes : le user teste **sans
/// câble**, `adb logcat` est donc hors d'atteinte, et les décisions qui font
/// apparaître ou non le chip se prennent toutes en Kotlin (autorisation de
/// démarrer un service de premier plan, acceptation du type `phoneCall`, pose
/// de la notification). `OngoingCallChip.journalise` recopie ces étapes dans
/// les préférences Flutter, `verserTracesChip()` les remonte ici.
///
/// ⚠️ À REPASSER À `false` une fois la cause trouvée. Le bandeau recouvre le
/// haut de l'écran et n'a rien à faire dans une version remise au user.
const bool tracesAppelsVisibles = true;

/// Trace de négociation d'appel : journal système ET overlay à l'écran.
///
/// Les deux, parce qu'ils ne servent pas au même moment : `adb logcat` donne
/// l'horodatage précis et l'historique complet, l'overlay permet de constater
/// sur le téléphone, sans câble, où la négociation s'arrête.
void traceAppel(String ligne) {
  debugPrint("[APPEL] $ligne");
  DebugOverlay.log("📞 $ligne");
}

/// Overlay de debug pour voir en live les événements WS et l'état du CallController.
/// À afficher au-dessus du Scaffold pendant le débogage des appels.
/// Retire ce widget en production.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key, required this.child});
  final Widget child;

  static final _log = <String>[];
  static final _controller = StreamController<void>.broadcast();

  /// Log une ligne. Appelable depuis n'importe où (RealtimeClient, CallController, etc.).
  static void log(String line) {
    // 🔴 FILTRE DE DIAGNOSTIC (24/08/2026) — À RETIRER AVEC
    // [tracesAppelsVisibles].
    //
    // Mesuré sur les captures du user : la négociation produit une QUINZAINE
    // de lignes ICE PAR SECONDE. À 60 lignes de journal, elles chassent les
    // lignes `CHIP` en moins de cinq secondes — l'utilisateur a vu passer
    // « chip retiré » sans jamais pouvoir le photographier.
    //
    // C'est le même piège que celui qui avait fait passer le journal de 20 à
    // 60 lignes en août, mais l'augmentation ne suffit plus : il faut écarter
    // le bruit, pas agrandir le seau. Les lignes ICE restent dans `adb logcat`
    // (`debugPrint`), où elles ne coûtent rien — seul l'AFFICHAGE les ignore.
    if (line.contains(' ice ') || line.endsWith('call_signal')) return;

    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$ts $line');
    // 60 et non 20 : une négociation produit une rafale de candidats ICE qui
    // chassait du journal les lignes décisives — dont l'offre elle-même, la
    // seule qu'on cherchait.
    if (_log.length > 60) _log.removeLast();
    _controller.add(null);
  }

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _expanded = true; // Ouvert par défaut pour ne rien rater
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = DebugOverlay._controller.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // `Positioned.fill` et non l'enfant nu : dans un `Stack`, un enfant
        // non positionné se dimensionne sur son propre contenu. L'application
        // entière doit occuper toute la surface, quoi qu'affiche l'overlay.
        Positioned.fill(child: widget.child),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 4,
          left: _expanded ? 4 : null,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🐛 DEBUG WS/CALL (tap pour réduire)',
                            style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (DebugOverlay._log.isEmpty)
                            const Text('(en attente…)',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 9)),
                          ...DebugOverlay._log.take(15).map(
                                (l) => Text(
                                  l,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                        ],
                      )
                    : const Text('🐛', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
