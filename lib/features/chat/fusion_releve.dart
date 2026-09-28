/// CE QUE LA RELÈVE APPORTE À L'ÉCRAN D'UNE CONVERSATION.
///
/// Fonction PURE, sortie de `chat_screen.dart` pour pouvoir être éprouvée
/// sans l'écran : `test/fusion_releve_test.dart`.
library;

import '../../models/message.dart';
import '../../services/e2ee/e2ee_fil.dart' show MessageClair;

/// Fusionne les messages relevés dans la liste affichée du fil [convId].
///
/// Deux cas, et le second manquait :
///
///   ① la bulle est DÉJÀ à l'écran, vide (sa ligne est arrivée par le temps
///     réel) → on lui donne son texte ;
///   ② la bulle N'EST PAS à l'écran → on l'ajoute.
///
/// 🐛 LE CAS ② N'EXISTAIT PAS. Un message chiffré est créé par la route REST,
/// qui ne diffuse rien : le destinataire ne reçoit PAS l'événement `message`
/// qui ajoute la bulle, seulement la sonnette `e2ee_arrivee`. La relève
/// déchiffrait bien le texte… et ne trouvait aucune bulle à remplir. Le message
/// n'apparaissait qu'en rouvrant la conversation (signalé le 28/09/2026).
///
/// ⚠️ ON NE REMPLACE JAMAIS UN TEXTE CONNU, et les messages des AUTRES fils
/// sont ignorés ici — la relève les a déjà rangés dans leur cache.
///
/// Rend la nouvelle liste, triée par date, et les messages AJOUTÉS (pour le
/// son et l'accusé de lecture).
({List<Message> liste, List<Message> ajoutes}) fusionnerReleve(
  List<Message> affiches,
  List<MessageClair> releves,
  String convId,
) {
  final textes = {for (final m in releves) m.id: m.texte};

  // ① Les bulles déjà là, vides : on leur donne leur texte. On reconstruit,
  // faute de `copyWith` sur le modèle.
  final remplis = [
    for (final m in affiches)
      if (textes[m.id] == null || (m.content ?? '').isNotEmpty)
        m
      else
        Message(
          id: m.id,
          chiffre: true,
          convId: m.convId,
          senderId: m.senderId,
          content: textes[m.id],
          type: m.type,
          status: m.status,
          replyToId: m.replyToId,
          media: m.media,
          createdAt: m.createdAt,
          deletedAt: m.deletedAt,
          editedAt: m.editedAt,
          expiresAt: m.expiresAt,
          replyTo: m.replyTo,
          reactions: m.reactions,
          starred: m.starred,
          mentions: m.mentions,
          statutCite: m.statutCite,
        ),
  ];

  // ② Les messages de CE fil que l'écran n'a pas : on les ajoute.
  final dejaLa = {for (final m in affiches) m.id};
  final ajoutes = [
    for (final m in releves)
      if (m.convId == convId && !dejaLa.contains(m.id))
        Message(
          id: m.id,
          chiffre: true,
          convId: m.convId,
          senderId: m.expediteurId,
          content: m.texte,
          type: 'TEXT',
          status: 'DELIVERED',
          replyToId: null,
          media: const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(m.quand),
        ),
  ];

  if (ajoutes.isEmpty) return (liste: remplis, ajoutes: ajoutes);
  return (
    liste: [...remplis, ...ajoutes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    ajoutes: ajoutes,
  );
}
