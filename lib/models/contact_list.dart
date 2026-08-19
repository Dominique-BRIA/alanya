/// Une liste de contacts personnalisée — « Famille », « Équipe », « Clients ».
///
/// ⚠️ MIROIR EXACT de `ListeJson` dans `backend-alanya/src/lib/contact-lists.ts`,
/// dont le commentaire dit lui-même que « les clients (web et Flutter) s'y
/// adossent au caractère près ». Toute évolution du format se décide là-bas
/// d'abord — c'est la parade à la panne des appels Web → Android, où une règle
/// partagée avait été modifiée d'un seul côté.
library;

import '../core/alanya_id_formatter.dart';

/// Un membre d'une liste.
///
/// ⚠️ `isContact` peut être FAUX : le serveur garde un membre dans ses listes
/// même s'il quitte le répertoire, précisément pour que le re-supprimer puis le
/// re-ajouter ne vide pas les listes où il figurait. Le client doit donc savoir
/// afficher quelqu'un qu'il ne connaît plus.
class MembreDeListe {
  const MembreDeListe({
    required this.id,
    required this.publicNumber,
    required this.name,
    required this.isContact,
  });

  final String id;
  final String publicNumber;

  /// Le nom connu, ou `null` si cette personne n'est plus dans le répertoire.
  final String? name;
  final bool isContact;

  /// Ce qu'on montre. Repli sur le numéro FORMATÉ, jamais brut — même règle que
  /// partout ailleurs depuis le 18/08/2026.
  String get displayName => name ?? formatAlanyaId(publicNumber);

  static MembreDeListe fromJson(Map<String, dynamic> j) => MembreDeListe(
        id: j["id"] as String,
        publicNumber: j["publicNumber"] as String? ?? "",
        name: j["name"] as String?,
        isContact: j["isContact"] as bool? ?? false,
      );
}

class ListeContacts {
  const ListeContacts({
    required this.id,
    required this.name,
    required this.ringtone,
    required this.color,
    required this.createdAt,
    required this.members,
  });

  final String id;
  final String name;

  /// URL relative de la sonnerie propre à cette liste, ou `null`.
  ///
  /// Le serveur n'en vérifie que la FORME, jamais le contenu. Le catalogue qui
  /// alimentera ce champ arrive avec l'import de sonneries.
  final String? ringtone;

  /// Couleur d'accent choisie par l'utilisateur, ou `null`.
  final String? color;

  final DateTime createdAt;
  final List<MembreDeListe> members;

  static ListeContacts fromJson(Map<String, dynamic> j) => ListeContacts(
        id: j["id"] as String,
        name: j["name"] as String? ?? "",
        ringtone: j["ringtone"] as String?,
        color: j["color"] as String?,
        // ⚠️ Repli sur MAINTENANT plutôt que de lever : une date illisible ne
        // doit pas faire disparaître une liste que l'utilisateur voit dans son
        // compte. Elle ne sert qu'à ordonner.
        createdAt: DateTime.tryParse(j["createdAt"] as String? ?? "") ??
            DateTime.now(),
        members: (j["members"] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(MembreDeListe.fromJson)
                .toList() ??
            const [],
      );
}
