import 'package:flutter/material.dart';

import '../../../widgets/selecteur_emojis.dart';

/// Choix d'un emoji, en feuille, pour décorer un statut.
///
/// ⚠️ LE MÊME SÉLECTEUR QUE LE CHAT ET LE WEB (02/10/2026). Cette feuille
/// portait sa propre liste écrite à la main — courte, et différente de celle
/// du chat. Elle reprend désormais le catalogue commun (1 812 emojis, 8
/// catégories, récents, recherche).

/// Ouvre la feuille et rend l'emoji choisi, ou `null` si l'on referme.
Future<String?> choisirEmoji(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    // Fond sombre : la feuille s'ouvre par-dessus un éditeur plein écran, lui
    // aussi sombre. Un fond clair ferait un éclair blanc à chaque ouverture.
    backgroundColor: const Color(0xFF1E1E1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _FeuilleEmoji(),
  );
}

class _FeuilleEmoji extends StatelessWidget {
  const _FeuilleEmoji();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        // Une demi-hauteur d'écran : assez pour balayer les familles, pas assez
        // pour cacher ce qu'on est en train de décorer. Le clavier, quand on
        // tape une recherche, remonte la feuille au lieu de la recouvrir.
        height: MediaQuery.of(context).size.height * 0.5 +
            MediaQuery.of(context).viewInsets.bottom,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SelecteurEmojis(
                  sombre: true,
                  onChoisir: (e) => Navigator.of(context).pop(e),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
