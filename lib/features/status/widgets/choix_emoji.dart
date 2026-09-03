import 'package:flutter/material.dart';

/// Choix d'un emoji, en feuille.
///
/// ⚠️ ÉCRIT À LA MAIN PLUTÔT QU'AVEC UN PAQUET, et c'est un choix. Un clavier
/// d'emojis complet (`emoji_picker_flutter` et consorts) apporte ses propres
/// polices, ses propres ressources et sa propre contrainte de version — pour
/// une grille de caractères que Flutter sait déjà dessiner. Le projet a trois
/// chaînes d'intégration à tenir accordées : une dépendance de plus se paie à
/// chaque montée de version.
///
/// La sélection est volontairement COURTE. Ce n'est pas un clavier : c'est le
/// nécessaire pour décorer un statut, rangé par usage et non par ordre Unicode.
const Map<String, List<String>> emojisParFamille = {
  "Visages": [
    "😀",
    "😁",
    "😂",
    "🤣",
    "😊",
    "😍",
    "🥰",
    "😎",
    "🤩",
    "😜",
    "🤗",
    "🤔",
    "😴",
    "😢",
    "😭",
    "😡",
    "🥳",
    "😱",
    "🤯",
    "🙄",
    "😇",
    "🤤",
    "😬",
    "🥺",
    "😤",
    "🤠",
    "🤓",
    "😷",
    "🤒",
    "😈",
  ],
  "Gestes": [
    "👍",
    "👎",
    "👏",
    "🙌",
    "🙏",
    "💪",
    "✌️",
    "🤞",
    "👌",
    "🤝",
    "👋",
    "🫶",
    "🤙",
    "☝️",
    "✋",
    "🖐️",
    "🤟",
    "👊",
    "🫰",
    "🫡",
  ],
  "Cœurs": [
    "❤️",
    "🧡",
    "💛",
    "💚",
    "💙",
    "💜",
    "🖤",
    "🤍",
    "🤎",
    "💔",
    "❣️",
    "💕",
    "💞",
    "💓",
    "💗",
    "💖",
    "💘",
    "💝",
    "💟",
    "♥️",
  ],
  "Nature": [
    "🔥",
    "✨",
    "⭐",
    "🌟",
    "💫",
    "☀️",
    "🌙",
    "☁️",
    "🌈",
    "⚡",
    "❄️",
    "🌊",
    "🌸",
    "🌺",
    "🌻",
    "🌹",
    "🌴",
    "🍀",
    "🌵",
    "🍁",
  ],
  "Animaux": [
    "🐶",
    "🐱",
    "🦁",
    "🐯",
    "🐴",
    "🦄",
    "🐘",
    "🐬",
    "🐳",
    "🦋",
    "🐝",
    "🐞",
    "🦅",
    "🦜",
    "🐍",
    "🐢",
    "🐐",
    "🐓",
    "🦈",
    "🐆",
  ],
  "Nourriture": [
    "🍏",
    "🍌",
    "🍇",
    "🍉",
    "🍓",
    "🍍",
    "🥑",
    "🌽",
    "🍞",
    "🧀",
    "🍗",
    "🍔",
    "🍟",
    "🍕",
    "🌮",
    "🍜",
    "🍚",
    "🍰",
    "🍫",
    "☕",
  ],
  "Objets": [
    "🎉",
    "🎊",
    "🎁",
    "🎈",
    "🏆",
    "🥇",
    "⚽",
    "🏀",
    "🎵",
    "🎸",
    "📱",
    "💻",
    "📷",
    "🚗",
    "✈️",
    "🚀",
    "💰",
    "💡",
    "🔑",
    "⏰",
  ],
  "Symboles": [
    "💯",
    "✅",
    "❌",
    "❓",
    "❗",
    "⚠️",
    "🚫",
    "♻️",
    "🔔",
    "🔕",
    "➕",
    "➖",
    "🔴",
    "🟢",
    "🔵",
    "🟡",
    "⬛",
    "⬜",
    "🔺",
    "🔻",
  ],
};

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
        // pour cacher ce qu'on est en train de décorer.
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final famille in emojisParFamille.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                      child: Text(
                        famille.key,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Wrap(
                      children: [
                        for (final e in famille.value)
                          InkWell(
                            onTap: () => Navigator.of(context).pop(e),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
