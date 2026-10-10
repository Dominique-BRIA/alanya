/// CE QUE LE CACHE LOCAL DOIT GARDER QUAND LE SERVEUR RÉPOND.
///
/// Fonctions PURES, éprouvées par `test/cache_clairs_test.dart`. Aucune
/// dépendance à `sqflite` : `MessageCache` lit les lignes, cette règle décide,
/// `MessageCache` écrit.
///
/// 🔴 LE TEXTE D'UN MESSAGE CHIFFRÉ N'EXISTE QU'ICI. Le serveur n'en garde que
/// la ligne, sans contenu ; la relève acquitte l'enveloppe après l'avoir rangée
/// dans le cache. Toute écriture qui remplace une ligne par la version du
/// serveur efface donc ce texte de l'appareil — seule l'archive chiffrée
/// permet ensuite de le retrouver.
library;

import '../models/message.dart';

/// La forme UNIQUE d'une date dans le cache : UTC, à la milliseconde.
///
/// 🐛 LE CACHE MÊLAIT DEUX FORMES. Une date du serveur y entrait en UTC
/// (« …09:14:36.000Z ») ; une date locale — message relevé, message envoyé —
/// en heure du téléphone, sans fuseau (« …10:14:36.000 » à Yaoundé, le même
/// instant). SQLite compare des chaînes : trié par `created_at`, un message
/// local passait une heure plus tard que sa place. Le dernier message d'un fil
/// pouvait donc être le mauvais.
///
/// ⚠️ LA MILLISECONDE, PAS LA MICROSECONDE : `toIso8601String` n'écrit les
/// microsecondes que si elles ne sont pas nulles. Deux largeurs différentes
/// casseraient à nouveau l'ordre des chaînes (« .123Z » > « .123456Z »).
String dateCache(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
  d.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

/// Une date déjà en cache, remise dans la forme de [dateCache].
///
/// Une chaîne sans fuseau a été écrite en heure du téléphone : `DateTime.parse`
/// la relit comme telle, ce qui rend le bon instant.
String dateNormalisee(String brute) => dateCache(DateTime.parse(brute));

/// Une ligne du cache, réduite à ce que la règle regarde.
class LigneCache {
  const LigneCache({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.chiffre,
  });

  final String id;
  final String? content;
  final DateTime createdAt;
  final bool chiffre;
}

/// Le plan de `MessageCache.putConv` : quoi effacer, quels textes recoller.
class PlanRemplacement {
  const PlanRemplacement({required this.aEffacer, required this.textes});

  /// Les lignes à supprimer du fil.
  final Set<String> aEffacer;

  /// Pour un message de la page arrivé sans texte : le texte connu localement.
  final Map<String, String> textes;
}

/// Le texte à écrire pour [nouveau], sachant que le cache avait [ancien].
///
/// 🐛 `putConv` et `upsert` REMPLAÇAIENT LA LIGNE ENTIÈRE par la version du
/// serveur, dont le contenu est nul pour un message chiffré : ouvrir la
/// conversation, ou remonter son historique, effaçait le texte déchiffré.
///
/// ⚠️ UN MESSAGE SUPPRIMÉ POUR TOUS PERD SON TEXTE, CHIFFRÉ OU NON : c'est le
/// sens même de la suppression.
String? texteAEcrire(Message nouveau, String? ancien) {
  if ((nouveau.content ?? '').isNotEmpty) return nouveau.content;
  if (nouveau.deletedAt != null) return null;
  if ((ancien ?? '').isEmpty) return nouveau.content;
  return ancien;
}

/// Ce que `putConv` fait des lignes déjà en cache, quand la page [page] du
/// serveur arrive.
///
/// 🐛 `putConv` VIDAIT LE FIL AVANT DE LE REMPLIR avec la dernière page. Pour
/// un fil ordinaire, sans perte : le serveur garde les messages plus anciens.
/// Pour un fil chiffré, chaque ouverture effaçait tous les textes déchiffrés
/// plus anciens que cette page.
///
/// La règle :
/// - une ligne de la page est remplacée (pas effacée), son texte connu gardé ;
/// - une ligne CHIFFRÉE, AVEC TEXTE, PLUS ANCIENNE que la page est gardée :
///   la page ne dit rien d'elle, et ce texte n'existe nulle part ailleurs ;
/// - toute autre ligne absente de la page est effacée — comme avant. Plus
///   récente que le début de la page, son absence veut dire que le message
///   n'existe plus pour nous (masqué, expiré).
///
/// ⚠️ PAGE VIDE : le serveur n'a plus aucun message à nous montrer dans ce
/// fil. Tout est effacé, textes chiffrés compris.
PlanRemplacement planRemplacement(
  List<LigneCache> existantes,
  List<Message> page,
) {
  final idsPage = {for (final m in page) m.id};
  DateTime? debutPage;
  for (final m in page) {
    if (debutPage == null || m.createdAt.isBefore(debutPage)) {
      debutPage = m.createdAt;
    }
  }

  final parId = {for (final l in existantes) l.id: l};
  final textes = <String, String>{};
  for (final m in page) {
    final ancien = parId[m.id]?.content;
    final texte = texteAEcrire(m, ancien);
    if (texte != null && texte != m.content) textes[m.id] = texte;
  }

  final aEffacer = <String>{};
  for (final l in existantes) {
    if (idsPage.contains(l.id)) continue;
    final aGarder =
        debutPage != null &&
        l.chiffre &&
        (l.content ?? '').isNotEmpty &&
        l.createdAt.isBefore(debutPage);
    if (!aGarder) aEffacer.add(l.id);
  }

  return PlanRemplacement(aEffacer: aEffacer, textes: textes);
}
