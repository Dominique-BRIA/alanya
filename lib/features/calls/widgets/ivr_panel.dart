import 'package:flutter/material.dart';

import '../../../theme/alanya_theme.dart';
import '../call_controller.dart';

/// Menu d'un standard téléphonique, affiché DANS l'écran d'appel.
///
/// Quatre états, comme n'importe quel vrai serveur vocal :
///
/// ```
/// menu ──(appui)──► envoi ──(ivr_hold)──► attente ──(décrochage)──► appel
///   ▲                 │
///   └──(erreur avec retour possible)──┘
/// ```
///
/// L'état « appel » n'apparaît pas ici : quand l'agent décroche, la session
/// disparaît du contrôleur et ce panneau avec elle. L'écran d'appel qui le
/// portait était déjà à l'écran — il n'y a rien à ouvrir, rien à préparer.
class IvrPanel extends StatelessWidget {
  const IvrPanel({
    super.key,
    required this.session,
    required this.onTouche,
  });

  final IvrSession session;
  final Future<void> Function(int digit) onTouche;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: session.etape == IvrEtape.attente
          ? _attente(context)
          : _menu(context),
    );
  }

  // ── Menu : la liste des touches ──────────────────────────────────────────

  Widget _menu(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (session.message != null) ...[
          _bandeauMessage(session.message!),
          const SizedBox(height: 14),
        ],
        Flexible(
          child: session.options.isEmpty
              ? const Text(
                  "Aucun service disponible.",
                  style: TextStyle(color: Colors.white70),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: session.options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _touche(session.options[i]),
                ),
        ),
        const SizedBox(height: 10),
        Text(
          session.envoiEnCours
              ? "Envoi de votre choix…"
              : "Choisissez un service",
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  /// Une touche du menu.
  ///
  /// Une option indisponible reste APPUYABLE, et c'est délibéré : l'invite
  /// vocale vient de l'annoncer, la désactiver laisserait l'appelant sans
  /// explication. Le serveur, lui, répond précisément pourquoi — et c'est lui
  /// qui fait autorité, pas ce qu'on pourrait deviner ici.
  Widget _touche(IvrOption option) {
    final grise = !option.disponible;
    final verrouille = session.envoiEnCours;
    return Opacity(
      opacity: grise ? 0.55 : 1,
      child: Material(
        color: Colors.white.withValues(alpha: grise ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // Verrouillé pendant l'envoi : sur un réseau lent l'utilisateur
          // insiste, et deux appuis feraient sonner deux agents pour une seule
          // intention.
          onTap: verrouille ? null : () => onTouche(option.digit),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: grise ? Colors.white24 : AlanyaColors.forest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${option.digit}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      if (grise)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            "Bientôt disponible",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!grise)
                  const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Attente : l'agent sonne ──────────────────────────────────────────────

  Widget _attente(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(AlanyaColors.forest),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          session.serviceChoisi ?? "Mise en relation",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Nous vous mettons en relation.\nMerci de patienter.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }

  Widget _bandeauMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
      ),
    );
  }
}
