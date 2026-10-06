/// CE QUE LA RELÈVE APPORTE À L'ÉCRAN D'UNE CONVERSATION.
///
/// Fonction PURE, sortie de `chat_screen.dart` pour pouvoir être éprouvée
/// sans l'écran : `test/fusion_releve_test.dart`.
library;

import '../../models/message.dart';
import '../../services/e2ee/e2ee_fil.dart' show MessageClair;
import '../../services/e2ee/e2ee_media.dart'
    show ligneMediaChiffre, typeMessagePour;

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
  /*
   * 🔴 LE TEXTE NE VA QU'À LA BULLE DE SON EXPÉDITEUR, DANS SON FIL.
   *
   * 🐛 L'identifiant du message vient du serveur, hors du chiffré : un serveur
   * malveillant rattachait le texte de Bob à une bulle d'Alice. L'expéditeur,
   * lui, est sûr — c'est sa session qui a déchiffré. Même règle que le web
   * (`clairPour`, `e2ee-etat-memorise.mjs` ⑤).
   */
  final parId = {for (final m in releves) m.id: m};
  MessageClair? releveDe(Message m) {
    final r = parId[m.id];
    if (r == null || r.expediteurId != m.senderId || r.convId != m.convId) return null;
    return r;
  }

  /*
   * Une bulle se complète si l'enveloppe apporte ce qui lui MANQUE : son
   * texte, ou — chapitre 23 — le descripteur de son média chiffré. Jamais on
   * ne remplace ce qui est déjà là.
   */
  bool aCompleter(Message m) {
    final r = releveDe(m);
    if (r == null || m.deletedAt != null) return false;
    return (m.content ?? '').isEmpty || (m.mediaChiffre == null && r.media != null);
  }


  // ① Les bulles déjà là, vides : on leur donne leur texte. On reconstruit,
  // faute de `copyWith` sur le modèle.
  final remplis = [
    for (final m in affiches)
      // ⚠️ Une bulle supprimée reste vide : l'enveloppe a pu arriver après.
      if (!aCompleter(m))
        m
      else
        Message(
          id: m.id,
          chiffre: true,
          convId: m.convId,
          senderId: m.senderId,
          content: (m.content ?? '').isEmpty ? releveDe(m)!.texte : m.content,
          // La ligne du serveur a déjà son type ; la charge le complète si
          // une version ancienne l'avait rangée en TEXT.
          type: m.type == 'TEXT' ? (releveDe(m)!.genre ?? m.type) : m.type,
          status: m.status,
          replyToId: m.replyToId ?? releveDe(m)!.reponseA,
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
          vueUnique: m.vueUnique,
          vueUniqueOuverte: m.vueUniqueOuverte,
          vueUniqueEffacee: m.vueUniqueEffacee,
          mediaChiffre: m.mediaChiffre ?? releveDe(m)!.media,
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
          // Un média relevé arrive complet : son type, et la ligne de média
          // qu'aurait rendue le serveur, marquée chiffrée.
          type: m.genre ?? typeMessagePour(m.media),
          status: 'DELIVERED',
          // 🐛 TOUJOURS `null` : une réponse relevée perdait sa citation
          // jusqu'à la réouverture du fil (06/10/2026).
          replyToId: m.reponseA,
          media: m.media == null
              ? const []
              : [MessageMedia.fromJson(ligneMediaChiffre(m.media!))],
          createdAt: DateTime.fromMillisecondsSinceEpoch(m.quand),
          mediaChiffre: m.media,
        ),
  ];

  if (ajoutes.isEmpty) return (liste: remplis, ajoutes: ajoutes);
  return (
    liste: [...remplis, ...ajoutes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    ajoutes: ajoutes,
  );
}
