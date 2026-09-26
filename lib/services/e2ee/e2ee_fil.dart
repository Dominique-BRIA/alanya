/// LE CHIFFREMENT BRANCHÉ AU FIL DE DISCUSSION — tickets 4.7 à 4.10.
///
/// 🔴 CE FICHIER EST CE QUI MANQUAIT. Les services du protocole existaient, mais
/// rien ne les appelait : aucun message ne partait chiffré, aucun n'arrivait.
/// C'est ici que le chiffrement cesse d'être une bibliothèque pour devenir une
/// fonctionnalité.
///
/// ⚠️ IL EST LE JUMEAU DE `STAGE-WEB/src/services/e2ee-fil.ts`. Toute règle
/// changée ici doit l'être là — et l'inverse. Les deux clients parlent aux mêmes
/// routes, et une divergence produirait des messages qu'un seul des deux sait
/// lire.
library;

import 'e2ee_service.dart';

/// Un message tel que le fil le manipule, en clair.
typedef MessageClair = ({String id, String convId, String texte, int quand});

/// Les types de compte couverts par le chiffrement.
///
/// 🔴 UNE LISTE BLANCHE, JAMAIS UNE LISTE NOIRE. Le jour où un type de compte
/// est ajouté, il est EXCLU par défaut — il faut un geste conscient pour
/// l'inclure. Une liste noire l'aurait inclus par oubli, et un centre d'appels
/// se serait retrouvé avec des conversations que l'organisation ne peut plus
/// lire.
const Set<int> typesPersonnels = {0};

bool estComptePersonnel(int? typeCompte) => typesPersonnels.contains(typeCompte);

/// Pourquoi une conversation ne peut pas être chiffrée.
enum MotifRefus { horsPerimetre, groupeNonSupporte }

/// Décide si une conversation entre dans le périmètre.
///
/// ⚠️ LES GROUPES SONT EXCLUS, et ce n'est pas une paresse : ils demanderaient
/// les Sender Keys, c'est-à-dire un SECOND protocole, pas une extension du
/// premier.
MotifRefus? motifRefus({
  required bool estGroupe,
  required List<int?> typesDesParticipants,
}) {
  if (typesDesParticipants.any((t) => !estComptePersonnel(t))) {
    return MotifRefus.horsPerimetre;
  }
  if (estGroupe) return MotifRefus.groupeNonSupporte;
  return null;
}

/// Le fil chiffré : ce que l'écran de conversation appelle.
class E2eeFil {
  E2eeFil(this._service, this._api, {this.monDeviceId = 1});

  /// ⚠️ LE DÉPÔT EXIGE L APPAREIL EXPÉDITEUR : le serveur s en sert pour ne pas
  /// nous renvoyer nos propres enveloppes, et pour que le destinataire sache
  /// quelle session ouvrir.
  final int monDeviceId;

  final E2eeService _service;
  final Future<Map<String, dynamic>> Function(
    String methode,
    String chemin,
    Map<String, dynamic>? corps,
  ) _api;

  /// Les conversations qu'on sait chiffrées, pour ne pas redemander au serveur.
  final Map<String, bool> _chiffrees = {};

  bool estChiffree(String convId) => _chiffrees[convId] ?? false;
  void noteEtat(String convId, bool actif) => _chiffrees[convId] = actif;

  /// Combien de conversations chiffrées ce compte a-t-il ?
  ///
  /// ⚠️ SERT À SAVOIR S'IL Y A QUELQUE CHOSE À PERDRE avant une déconnexion —
  /// même usage que sur le web.
  int conversationsChiffrees() => _chiffrees.values.where((a) => a).length;

  /* ══════════════ ENVOYER ══════════════ */

  /// Envoie un message dans un fil chiffré.
  ///
  /// 🔴 UNE ENVELOPPE PAR APPAREIL DESTINATAIRE. Bob peut avoir un téléphone ET
  /// un navigateur : chacun a sa propre identité, donc sa propre session, donc
  /// son propre chiffré. En produire une seule condamnerait l'un des deux au
  /// silence.
  ///
  /// 🔴 LE CLAIR NE PART JAMAIS. Si le chiffrement échoue — pour un seul
  /// appareil comme pour tous — on LÈVE. L'appelant affiche l'échec ; il ne
  /// retombe pas en clair.
  ///
  /// ⚠️ C'EST LA RÈGLE LA PLUS IMPORTANTE DU FICHIER. Un repli silencieux vers
  /// le clair est exactement ce qu'un attaquant cherche à provoquer : il suffit
  /// de faire échouer le chiffrement pour lire.
  Future<String> envoyer({
    required String convId,
    required String pairId,
    required String texte,
  }) async {
    var appareils = await _service.ouvrirSessions(pairId);

    if (appareils.isEmpty) {
      /*
       * ⚠️ AUCUN APPAREIL PUBLIÉ : le correspondant n'a jamais ouvert
       * l'application, ou ses clés ont expiré. On refuse, on ne contourne pas.
       */
      throw const E2eeImpossible('Aucun appareil chiffré chez ce correspondant.');
    }

    final enveloppes = <Map<String, dynamic>>[];
    for (final deviceId in appareils) {
      final e = await _service.chiffrer(pairId, deviceId, texte);
      enveloppes.add({
        'destinataireDevice': deviceId,
        'type': e.type,
        'corps': e.corps,
      });
    }

    /*
     * 🐛 J'AVAIS INVENTÉ `POST /api/messages/chiffre`. Cette route n'existe pas.
     * Le vrai chemin est celui du web, et il tient en DEUX appels :
     *
     *   ① la ligne du fil, SANS contenu — le serveur la refuserait autrement ;
     *   ② les enveloppes, rattachées à cette ligne.
     *
     * ⚠️ DANS CET ORDRE, ET PAS L'INVERSE. Une enveloppe sans message auquel se
     * rattacher serait orpheline ; un message sans enveloppe s'afficherait vide
     * chez le destinataire.
     */
    final message = await _api('POST', '/api/conversations/$convId/messages', {
      'type': 'TEXT',
      'chiffre': true,
    });
    final messageId = message['id'] as String;

    await _api('POST', '/api/e2ee/enveloppes', {
      'convId': convId,
      'deviceId': monDeviceId,
      'enveloppes': enveloppes,
      'messageId': messageId,
    });

    return messageId;
  }

  /* ══════════════ RECEVOIR ══════════════ */

  /// Relève les enveloppes en attente et les déchiffre.
  ///
  /// ⚠️ ON ACQUITTE APRÈS AVOIR DÉCHIFFRÉ, JAMAIS AVANT. Une enveloppe acquittée
  /// est définitivement perdue : le ratchet a avancé et la clé du message est
  /// détruite. Acquitter d'abord ferait disparaître un message qu'on n'a pas
  /// réussi à lire.
  ///
  /// ⚠️ UNE ENVELOPPE ILLISIBLE NE BLOQUE PAS LES AUTRES. On la compte et on
  /// continue : un message perdu vaut mieux qu'un fil entier qui ne charge plus.
  Future<({List<MessageClair> messages, int illisibles})> relever() async {
    final r = await _api('GET', '/api/e2ee/enveloppes', null);
    final brutes = (r['enveloppes'] as List).cast<Map<String, dynamic>>();

    final messages = <MessageClair>[];
    final aAcquitter = <String>[];
    var illisibles = 0;

    for (final e in brutes) {
      try {
        final texte = await _service.dechiffrer(
          e['expediteurId'] as String,
          e['expediteurDevice'] as int,
          e['type'] as int,
          e['corps'] as String,
        );
        messages.add((
          id: e['messageId'] as String,
          convId: e['conversationId'] as String,
          texte: texte,
          quand: e['quand'] as int,
        ));
        aAcquitter.add(e['id'] as String);
        noteEtat(e['conversationId'] as String, true);
      } catch (_) {
        illisibles++;
      }
    }

    if (aAcquitter.isNotEmpty) {
      /*
       * 🐛 J'AVAIS INVENTÉ `POST .../acquitter`. L'acquittement est un DELETE et
       * les identifiants passent en PARAMÈTRE D'URL, séparés par des virgules —
       * c'est le contrat que le serveur applique déjà au web.
       */
      final ids = aAcquitter.join(',');
      await _api('DELETE', '/api/e2ee/enveloppes?ids=$ids', null);
    }
    return (messages: messages, illisibles: illisibles);
  }

  /* ══════════════ ACTIVER ══════════════ */

  /// Active le chiffrement sur une conversation.
  ///
  /// ⚠️ LES MESSAGES ANTÉRIEURS RESTENT LISIBLES, et une bannière doit le dire à
  /// l'écran : « à partir d'ici, chiffré ». Laisser croire que tout l'historique
  /// devient protégé serait un mensonge par omission.
  Future<void> activer(String convId) async {
    await _api('POST', '/api/conversations/$convId/e2ee', null);
    noteEtat(convId, true);
  }
}

/// Le chiffrement n'a pas pu se faire — et on ne retombe pas en clair.
class E2eeImpossible implements Exception {
  const E2eeImpossible(this.message);
  final String message;
  @override
  String toString() => message;
}
