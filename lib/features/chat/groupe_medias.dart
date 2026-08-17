import '../../models/message.dart';

/// Plusieurs messages de médias consécutifs, présentés comme UNE grille.
///
/// C'est un objet d'AFFICHAGE : rien n'est fusionné en base, chaque message
/// reste le sien. Il existe parce que le client web et l'application de
/// l'équipe n'envoient qu'un média par message — cinq photos arrivent en cinq
/// messages, et sans regroupement le fil les empile.
///
/// Chaque cellule de la grille doit pouvoir remonter à SON message : « répondre »,
/// « supprimer » ou « transférer » s'appliquent à un message, jamais à la
/// grille. D'où [messageDuMedia], et non une simple liste de médias.
class GroupeMedias {
  GroupeMedias(this.messages);

  /// Ordre chronologique, au moins deux éléments.
  final List<Message> messages;

  /// L'horodatage du groupe est celui du DERNIER message : c'est la position
  /// qu'il occupe dans le fil, et l'heure que l'utilisateur voit.
  DateTime get date => messages.last.createdAt;

  String get senderId => messages.first.senderId;

  /// Tous les médias à plat, dans l'ordre des messages.
  List<MessageMedia> get medias => [for (final m in messages) ...m.media];

  /// Message auquel appartient le média d'index [index] dans [medias].
  Message? messageDuMedia(int index) {
    var reste = index;
    for (final m in messages) {
      if (reste < m.media.length) return m;
      reste -= m.media.length;
    }
    return null;
  }

  /// Statut à afficher : celui du dernier message envoyé du groupe.
  String get statut => messages.last.status;
}
