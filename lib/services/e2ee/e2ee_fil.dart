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

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show DuplicateMessageException;

import 'e2ee_media.dart';
import 'e2ee_service.dart';

/// Un message tel que le fil le manipule, en clair.
typedef MessageClair = ({
  String id,
  String convId,
  String expediteurId,
  String texte,
  int quand,
  /// Le média chiffré que porte le message (charge v2), avec sa clé.
  DescripteurMedia? media,
  /// Le message auquel celui-ci répond, lu DANS la charge (06/10/2026).
  String? reponseA,
  /// CONTACT ou LOCATION : [texte] porte alors la fiche JSON.
  String? genre,
  /// [texte] REMPLACE celui du message (modification, 07/10/2026).
  bool modifie,
});

/// Range des messages relevés — appelé AVANT leur acquittement.
typedef Rangement = Future<void> Function(List<MessageClair> messages);

/// Ce que vaut l'échec d'un déchiffrement.
enum _Echec {
  /// Le message a DÉJÀ été ouvert : rien de perdu, rien à réparer.
  dejaLu,

  /// Le stockage n'a pas répondu à temps : réessayer peut réussir.
  passager,

  /// Plus rien ne l'ouvrira jamais : réessayer ne sert à rien.
  definitif,
}

/// Classe un échec de déchiffrement.
///
/// ⚠️ LA LISTE EST À L'ENVERS, ET C'EST VOULU. La bibliothèque n'exporte pas
/// ses exceptions de message invalide (`InvalidMessageException`,
/// `InvalidMacException`) : on ne peut pas les nommer. On nomme donc ce qui est
/// PASSAGER — un délai dépassé, une panne du coffre sécurisé —, et tout le
/// reste est définitif.
///
/// 🔴 UN DÉFINITIF TENU POUR PASSAGER, C'EST LA BOUCLE qu'on vient de fermer :
/// l'enveloppe reste en tête de file et revient à chaque relève. Un passager
/// tenu pour définitif, c'est un message perdu. D'où une liste courte et
/// précise du côté passager.
_Echec _natureDe(Object e) {
  if (e is DuplicateMessageException) return _Echec.dejaLu;
  if (e is TimeoutException || e is PlatformException) return _Echec.passager;
  return _Echec.definitif;
}

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
  E2eeFil(this._service, this._api, this._monDeviceId, {this.monCompte});

  /// Mon compte — pour chiffrer aussi vers MES autres appareils. Sans lui,
  /// seul le correspondant reçoit le message.
  final String? monCompte;

  /// L'appareil que NOUS sommes, tel qu'il a été publié.
  ///
  /// 🔴 C'ÉTAIT `{this.monDeviceId = 1}` — UNE VALEUR PAR DÉFAUT, ET PERSONNE
  /// NE LA REMPLAÇAIT. `PileE2ee.pour` construisait `E2eeFil(service, appel)`
  /// sans rien passer : tout le mobile se déclarait donc appareil n° 1, alors
  /// que son identifiant réel est tiré au sort à l'installation.
  ///
  /// 🐛 Conséquence sur la RELÈVE : les enveloppes sont rangées par
  /// `destinataireDevice`, c'est-à-dire par le numéro PUBLIÉ. En demander
  /// celles de l'appareil 1 n'aurait rien rendu, même une fois le paramètre
  /// ajouté.
  ///
  /// ⚠️ UNE FONCTION, PAS UN NOMBRE : le numéro vit dans le coffre sécurisé et
  /// se lit de façon asynchrone, alors que la pile se construit d'un trait.
  /// C'est ce qui avait fait choisir une valeur par défaut — et une valeur par
  /// défaut qui décide à votre place finit toujours par décider mal.
  final Future<int> Function() _monDeviceId;

  final E2eeService _service;
  final Future<Map<String, dynamic>> Function(
    String methode,
    String chemin,
    Map<String, dynamic>? corps,
  ) _api;

  /// Les conversations qu'on sait chiffrées, pour ne pas redemander au serveur.
  final Map<String, bool> _chiffrees = {};

  /*
   * ══════════════ UN FIL CHIFFRÉ LE RESTE — LE CLIENT S'EN SOUVIENT ══════════════
   *
   * 🐛 LE SERVEUR ÉTAIT SEUL JUGE, et sa réponse ne vivait qu'en mémoire. Un
   * serveur compromis qui répondait « non chiffré » faisait repartir le texte
   * en clair ; et à chaque lancement, l'écran repartait de « non chiffré » le
   * temps que le serveur réponde. Prouvé par `test/e2ee_releve_test.dart` ⑧.
   *
   * 🔴 UN FIL VU CHIFFRÉ UNE FOIS NE REDESCEND JAMAIS : aucune route du serveur
   * ne désactive le chiffrement d'un fil. Même règle que le web
   * (`STAGE-WEB/src/services/e2ee-fil.ts`).
   *
   * ⚠️ DANS LE COFFRE, donc par compte, et effacé avec lui.
   */
  final Set<String> _memorises = {};
  Future<void>? _chargement;

  /// Charge la mémoire des fils chiffrés. Idempotente ; ne lève jamais.
  Future<void> chargerMemoire() => _chargement ??= () async {
        try {
          _memorises.addAll(await _service.coffre.filsChiffres());
        } catch (_) {
          // Coffre muet : on garde la mémoire de la session, rien de pire.
        }
      }();

  /// Connaît-on l'état de ce fil ? Tant que non, on n'envoie pas en clair.
  bool etatConnu(String convId) =>
      _chiffrees.containsKey(convId) || _memorises.contains(convId);

  bool estChiffree(String convId) =>
      _chiffrees[convId] == true || _memorises.contains(convId);

  void noteEtat(String convId, bool actif) {
    if (actif) {
      _chiffrees[convId] = true;
      if (_memorises.add(convId)) {
        final fils = {..._memorises};
        unawaited(_service.coffre.memoriserFilsChiffres(fils).catchError((_) {}));
      }
      return;
    }
    // ⚠️ « Non chiffré » après « chiffré » : ignoré, voir ci-dessus.
    if (estChiffree(convId)) return;
    _chiffrees[convId] = false;
  }

  /// Combien de conversations chiffrées ce compte a-t-il ?
  ///
  /// ⚠️ SERT À SAVOIR S'IL Y A QUELQUE CHOSE À PERDRE avant une déconnexion —
  /// même usage que sur le web.
  int conversationsChiffrees() => {
        ..._memorises,
        for (final e in _chiffrees.entries)
          if (e.value) e.key,
      }.length;

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
    /// 🐛 LA RÉPONSE ET LE CONTACT N'EXISTAIENT PAS DANS UN FIL CHIFFRÉ (user,
    /// 06/10/2026) : la citation n'était jamais transmise, et un contact
    /// partait en clair — refusé par le serveur. [type] vaut `CONTACT` ou
    /// `LOCATION` quand [texte] porte une fiche JSON.
    String type = 'TEXT',
    String? replyToId,
  }) async {
    var appareils = await _service.ouvrirSessions(pairId);

    if (appareils.isEmpty) {
      /*
       * ⚠️ AUCUN APPAREIL PUBLIÉ : le correspondant n'a jamais ouvert
       * l'application, ou ses clés ont expiré. On refuse, on ne contourne pas.
       */
      throw const E2eeImpossible('Aucun appareil chiffré chez ce correspondant.');
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
      'type': type,
      'chiffre': true,
      if (replyToId != null) 'replyToId': replyToId,
    });
    final messageId = message['id'] as String;

    /*
     * 🔴 LE TEXTE PART EN CHARGE v2, AVEC L'IDENTIFIANT DU MESSAGE DEDANS
     * (lot D, chapitre 26). En v1, l'identifiant ne voyageait qu'À CÔTÉ du
     * chiffré : le serveur pouvait rattacher le texte de Bob à un AUTRE
     * message de Bob du même fil. Chiffré avec le texte, il est hors de sa
     * portée, et `lireCharge` refuse une enveloppe mal rattachée.
     *
     * ⚠️ D'OÙ LE CHIFFREMENT APRÈS LA LIGNE, et non plus avant : il faut
     * l'identifiant pour écrire la charge. C'était déjà l'ordre du média
     * (lot C) et celui du web. Les sessions, elles, sont ouvertes plus haut,
     * avant la ligne : c'est là que l'échec est probable (réseau, pré-clés).
     */
    final enveloppes =
        await _enveloppesPour(pairId, appareils,
            ecrireCharge(messageId, texte, null, replyToId, type == 'TEXT' ? null : type));

    await _api('POST', '/api/e2ee/enveloppes', {
      'convId': convId,
      'deviceId': await _monDeviceId(),
      'enveloppes': enveloppes,
      'messageId': messageId,
    });

    return messageId;
  }

  /// Les enveloppes d'un clair : une par appareil du correspondant, puis une
  /// par AUTRE appareil de mon compte. Commun au texte et aux médias.
  /// MODIFIER UN MESSAGE CHIFFRÉ (07/10/2026) — cours, chapitre 29.
  ///
  /// 🐛 « Modifier le message ne donne plus » : le serveur refusait toute
  /// modification dans un fil chiffré — il n'a pas le texte, il ne peut pas le
  /// remplacer. Le nouveau texte part donc comme un message : dans des
  /// ENVELOPPES rattachées au MÊME message, avec `modifie: true` dans la charge.
  /// Le serveur, lui, ne fait que dater la modification.
  ///
  /// ⚠️ DANS CET ORDRE : la date d'abord, les enveloppes ensuite. Le
  /// destinataire relève dès la sonnette qui suit le dépôt ; la ligne doit
  /// déjà dire « modifié ».
  ///
  /// Rend la date de modification du serveur.
  Future<DateTime?> modifier({
    required String convId,
    required String pairId,
    required String messageId,
    required String texte,
  }) async {
    final appareils = await _service.ouvrirSessions(pairId);
    if (appareils.isEmpty) {
      throw const E2eeImpossible('Aucun appareil chiffré chez ce correspondant.');
    }
    final r = await _api(
        'PATCH', '/api/conversations/$convId/messages/$messageId', {'chiffre': true});
    final enveloppes = await _enveloppesPour(
        pairId, appareils, ecrireCharge(messageId, texte, null, null, null, true));
    await _api('POST', '/api/e2ee/enveloppes', {
      'convId': convId,
      'deviceId': await _monDeviceId(),
      'enveloppes': enveloppes,
      'messageId': messageId,
    });
    return DateTime.tryParse('${r['editedAt']}');
  }

  Future<List<Map<String, dynamic>>> _enveloppesPour(
    String pairId,
    List<int> appareils,
    String clair,
  ) async {
    final enveloppes = <Map<String, dynamic>>[];
    for (final deviceId in appareils) {
      final e = await _service.chiffrer(pairId, deviceId, clair);
      /*
       * 🐛 `destinataireId` MANQUAIT. Le serveur refuse l'enveloppe sans lui —
       * il ne peut pas deviner à QUI la remettre à partir du seul numéro
       * d'appareil, qui n'est unique que par personne.
       */
      enveloppes.add({
        'destinataireId': pairId,
        'destinataireDevice': deviceId,
        'type': e.type,
        'corps': e.corps,
      });
    }

    /*
     * Et une enveloppe pour chacun de MES AUTRES appareils.
     *
     * 🐛 ON NE CHIFFRAIT QUE POUR LE CORRESPONDANT : un message écrit d'ici
     * n'arrivait jamais sur le navigateur du même compte. Prouvé par
     * `test/e2ee_releve_test.dart`, groupe ⑥. Jumeau du web.
     *
     * ⚠️ CET appareil est exclu, et un échec ici n'empêche pas l'envoi : le
     * correspondant doit recevoir son message même si mon autre appareil est
     * injoignable — celui-ci le rattrapera par l'archive.
     */
    final moi = monCompte;
    if (moi != null && moi != pairId) {
      try {
        final miens =
            await _service.ouvrirSessions(moi, exclure: await _monDeviceId());
        for (final deviceId in miens) {
          final e = await _service.chiffrer(moi, deviceId, clair);
          enveloppes.add({
            'destinataireId': moi,
            'destinataireDevice': deviceId,
            'type': e.type,
            'corps': e.corps,
          });
        }
      } catch (_) {}
    }
    return enveloppes;
  }

  /// Envoie un MÉDIA chiffré de bout en bout — cours, chapitre 25 (lot C).
  ///
  /// Le fichier est DÉJÀ chiffré et téléversé (`media.id`) ; restent la ligne
  /// du message et les enveloppes portant la charge v2 : clé, empreinte,
  /// aperçu, légende.
  ///
  /// La ligne d'abord, les enveloppes ensuite — comme le texte depuis le
  /// lot D : la charge v2 porte l'identifiant du message, il faut donc l'avoir
  /// avant de chiffrer. Jumeau de `envoyerMediaChiffre` côté web.
  Future<String> envoyerMedia({
    required String convId,
    required String pairId,
    required DescripteurMedia media,
    String legende = '',
    String? replyToId,
    bool vueUnique = false,
  }) async {
    final appareils = await _service.ouvrirSessions(pairId);
    if (appareils.isEmpty) {
      throw const E2eeImpossible('Aucun appareil chiffré chez ce correspondant.');
    }
    final message = await _api('POST', '/api/conversations/$convId/messages', {
      'type': typeMessagePour(media),
      'chiffre': true,
      'mediaIds': [media.id],
      if (replyToId != null) 'replyToId': replyToId,
      if (vueUnique) 'vueUnique': true,
    });
    final messageId = message['id'] as String;
    final enveloppes =
        await _enveloppesPour(pairId, appareils, ecrireCharge(messageId, legende, media, replyToId));
    await _api('POST', '/api/e2ee/enveloppes', {
      'convId': convId,
      'deviceId': await _monDeviceId(),
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
  ///
  /// 🔴 [ranger] PASSE AVANT L'ACQUITTEMENT, ET IL REÇOIT TOUS LES FILS.
  ///
  /// 🐛 La relève ramène les enveloppes de TOUTES les conversations. L'écran ne
  /// rangeait que celles du fil ouvert : le texte des autres était acquitté
  /// puis jeté, et son fil affichait ensuite « indisponible sur cet appareil ».
  /// Même défaut sur le web, prouvé le 28/09/2026
  /// (`STAGE-WEB/scripts/e2ee-releve-multifil.mjs`).
  ///
  /// 🔴 LES RELÈVES PASSENT UNE PAR UNE.
  ///
  /// 🐛 L'écran en lance jusqu'à trois sans les attendre — ouverture du fil,
  /// ligne du message, sonnette `e2ee_arrivee` —, et les deux dernières partent
  /// pour le MÊME message. Tant que la première n'a pas acquitté, la seconde
  /// ramène les mêmes enveloppes, les déchiffre une deuxième fois, échoue, et
  /// l'échec effaçait la session : le message suivant du correspondant était
  /// perdu. Prouvé par `test/e2ee_releve_test.dart`, groupe ①.
  ///
  /// ⚠️ UNE FILE, PAS UNE RELÈVE PARTAGÉE : un appel arrivé en cours de route
  /// peut viser une enveloppe déposée après le départ de la relève en cours.
  Future<({List<MessageClair> messages, int illisibles})> relever({
    Rangement? ranger,
  }) {
    final tour = _fileReleves.then((_) => _releverMaintenant(ranger));
    _fileReleves = tour.then((_) {}, onError: (_) {});
    return tour;
  }

  Future<void> _fileReleves = Future<void>.value();

  Future<({List<MessageClair> messages, int illisibles})> _releverMaintenant(
    Rangement? ranger,
  ) async {
    /*
     * 🔴 `deviceId` EST OBLIGATOIRE, ET IL MANQUAIT.
     *
     * 🐛 Le serveur répondait `400 « deviceId » est requis`. L'exception
     * remontait dans `_releverChiffres`, qui la rattrape en silence : le mobile
     * n'a donc JAMAIS relevé une seule enveloppe. Les messages reçus
     * arrivaient par le temps réel, sans texte, et le restaient.
     *
     * ⚠️ `outils/contrat_routes.py` NE POUVAIT PAS LE VOIR : il compare le
     * verbe et le CHEMIN, et la chaîne de requête n'en fait pas partie. Un
     * paramètre obligatoire absent ressemble à un appel parfaitement valide.
     */
    final r = await _api(
      'GET', '/api/e2ee/enveloppes?deviceId=${await _monDeviceId()}', null);
    final brutes = listeDe(r, 'enveloppes');

    final messages = <MessageClair>[];
    final aAcquitter = <String>[];
    var illisibles = 0;
    // Une session n'est effacée qu'UNE fois par relève, même si plusieurs de
    // ses enveloppes échouent : la seconde effacerait ce que la première a
    // déjà remis à zéro, pour rien.
    final sessionsOubliees = <String>{};

    for (final e in brutes) {
      try {
        final texte = await _service.dechiffrer(
          e['expediteurId'] as String,
          e['expediteurDevice'] as int,
          e['type'] as int,
          e['corps'] as String,
        );
        /*
         * ⚠️ LES NOMS VIENNENT DU SERVEUR, PAS DE MON SOUVENIR : `convId` et
         * `createdAt`, vérifiés dans la route. Une clé mal orthographiée ne se
         * voit pas à la compilation — elle rend `null` à l'exécution.
         */
        /*
         * 🔴 LA CHARGE EST LUE ICI, ET VÉRIFIÉE (cours, chapitre 23). Un texte
         * nu (v1) passe tel quel ; une charge v2 doit annoncer CE message — un
         * serveur qui l'aurait rattachée à un autre est démasqué, et
         * l'enveloppe tombe dans le `catch` : illisible, acquittée.
         */
        final charge = lireCharge(texte, e['messageId'] as String?);
        final clair = (
          id: (e['messageId'] ?? e['id']) as String,
          convId: e['convId'] as String,
          expediteurId: e['expediteurId'] as String,
          texte: charge.texte,
          quand: DateTime.parse(e['createdAt'] as String).millisecondsSinceEpoch,
          media: charge.media,
          reponseA: charge.reponseA,
          genre: charge.genre,
          modifie: charge.modifie,
        );
        messages.add(clair);
        /*
         * 🔴 RANGÉ AUSSITÔT, AVANT LE MESSAGE SUIVANT.
         *
         * 🐛 TOUT LE LOT ÉTAIT DÉCHIFFRÉ, PUIS RANGÉ D'UN COUP — jusqu'à deux
         * cents messages. Android qui tuait l'application entre les deux
         * perdait tous les textes déjà ouverts : le cliquet avait avancé, et
         * la relève suivante les prenait pour « déjà lus ». Ranger message par
         * message réduit cette fenêtre à un seul. Prouvé par
         * `test/e2ee_releve_test.dart`, groupe ③, le 28/09/2026.
         *
         * ⚠️ UN RANGEMENT RATÉ N'EMPÊCHE PAS L'ACQUITTEMENT. Garder l'enveloppe
         * ne sauverait rien — elle ne se relirait plus — et la remettrait en
         * tête de file. Le texte reste au moins dans ce que rend la relève.
         */
        if (ranger != null) {
          try {
            await ranger([clair]);
          } catch (_) {}
        }
        aAcquitter.add(e['id'] as String);
        noteEtat(e['convId'] as String, true);
      } catch (erreur) {
        final nature = _natureDe(erreur);

        /*
         * ⚠️ PASSAGER : ON GARDE L'ENVELOPPE, ET ON NE TOUCHE À RIEN. Le coffre
         * n'a pas répondu à temps ; le message est intact, la prochaine relève
         * le lira. Effacer la session ici détruirait une session saine.
         */
        if (nature == _Echec.passager) continue;

        /*
         * 🔴 DÉFINITIF OU DÉJÀ LU : ON ACQUITTE.
         *
         * 🐛 L'ENVELOPPE ILLISIBLE N'ÉTAIT JAMAIS ACQUITTÉE. Elle revenait à
         * chaque relève, échouait de nouveau, et chaque échec effaçait la
         * session — y compris celle que le correspondant venait de rétablir.
         * La conversation restait cassée tant que l'enveloppe vivait sur le
         * serveur, soit jusqu'à 90 jours. Prouvé par le groupe ② du test.
         *
         * ⚠️ LA GARDER NE SAUVAIT RIEN : un message dont la session ou la clé
         * n'existe plus ne se lira pas mieux demain.
         */
        aAcquitter.add(e['id'] as String);

        // Déjà ouvert par une relève précédente : ni perte, ni divergence.
        if (nature == _Echec.dejaLu) continue;

        illisibles++;
        final cle = '${e['expediteurId']}.${e['expediteurDevice']}';
        if (!sessionsOubliees.add(cle)) continue;
        /*
         * 🔴 UNE ENVELOPPE ILLISIBLE VEUT DIRE QUE LES DEUX SESSIONS ONT
         * DIVERGÉ — et sans geste de notre part, ÇA NE SE RÉPARE JAMAIS.
         *
         * Le correspondant continue d'écrire avec SA session ; la nôtre ne
         * correspond plus. Chaque message suivant échouera pareil, en
         * silence, pour toujours.
         *
         * ⚠️ ON EFFACE DONC LA NÔTRE. Elle ne sert plus à rien, et son
         * absence force notre PROCHAIN envoi à repartir d'un X3DH complet —
         * un message de type 3, que le correspondant adopte. Les deux côtés
         * se retrouvent alors sur la même session.
         *
         * ⚠️ LE MESSAGE EN COURS RESTE PERDU : sa clé n'existe plus. On
         * répare la SUITE, pas le passé — et c'est pour cela que l'écran doit
         * le dire au lieu d'afficher une bulle vide.
         */
        try {
          await _service.oublierSession(
            e['expediteurId'] as String,
            e['expediteurDevice'] as int,
          );
        } catch (_) {
          // Le nettoyage ne doit pas empêcher de relever les suivantes.
        }
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

  /// L'état du chiffrement d'une conversation, tel que le serveur le donne.
  ///
  /// 🔴 ON NE LE DEVINE PAS DU CONTENU : un message ancien, arrivé en clair
  /// avant l'activation, ferait conclure que le fil ne l'est pas.
  Future<bool> etat(String convId) async {
    final r = await _api('GET', '/api/conversations/$convId/e2ee', null);
    noteEtat(convId, r['e2eeActif'] == true);
    // ⚠️ L'état RETENU, pas la réponse : un « non » ne défait pas un « oui ».
    return estChiffree(convId);
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
