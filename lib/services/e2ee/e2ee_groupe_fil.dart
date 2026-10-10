/// LE GROUPE CHIFFRÉ, BRANCHÉ AU FIL — lot 3 (mobile), cours chapitre 34.
///
/// ⚠️ JUMEAU DE `STAGE-WEB/src/services/e2ee-groupe-fil.ts`. Toute règle
/// changée ici doit l'être là.
///
/// La différence de fond avec le tête-à-tête :
///
///   · à deux, le texte voyage dans des ENVELOPPES (une par appareil),
///     consommées à la lecture : c'est le cache local qui garde le clair ;
///   · en groupe, UN SEUL chiffré par message, rangé par le serveur AVEC la
///     ligne et jamais consommé. Chaque membre le relit quand il veut, avec la
///     clé du groupe de la bonne version (le « trousseau »).
///
/// 🔴 LA SIGNATURE SE VÉRIFIE AVEC UNE CLÉ D'IDENTITÉ DÉJÀ CONNUE (chapitre
/// 32), celle de la session Signal à deux avec cet appareil. Inconnue, on ouvre
/// la session d'abord : c'est le chemin habituel, avec son alerte « clé
/// changée ».
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show SignalProtocolAddress;

import '../../core/api_client.dart' show ApiException;
import 'e2ee_groupe.dart' as g;
import 'e2ee_media.dart';
import 'e2ee_service.dart';
import 'e2ee_trousseau_perso.dart';

/// Le message n'est pas parti : la clé du groupe manque ou a changé.
class CleGroupeAbsente implements Exception {
  const CleGroupeAbsente();
  @override
  String toString() =>
      "Clé du groupe pas encore reçue : le message n'est pas parti. Réessayez dans un instant.";
}

/// Le clair d'un message de groupe.
typedef ClairGroupe = ({
  String texte,
  DescripteurMedia? media,
  String? reponseA,
  String? genre,
  bool modifie,
});

/// Pourquoi un message de groupe ne s'est pas ouvert.
enum EchecGroupe { cleAbsente, expediteurInconnu, invalide }

/// Un UUID v4, tiré au hasard sûr — l'identifiant d'un message de groupe est
/// choisi par l'appareil, car il est signé dans le chiffré.
String uuidV4() {
  final r = Random.secure();
  final o = List<int>.generate(16, (_) => r.nextInt(256));
  o[6] = (o[6] & 0x0f) | 0x40;
  o[8] = (o[8] & 0x3f) | 0x80;
  final h = o.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// La règle du serveur (`isGroupAdmin`), à l'identique : un ADMIN, ou — dans
/// un ancien groupe qui n'en a aucun — le premier arrivé.
bool estAdministrateur(List<Map<String, dynamic>> membres, String userId) {
  if (membres.any((m) => m['role'] == 'ADMIN')) {
    return membres.any((m) => m['id'] == userId && m['role'] == 'ADMIN');
  }
  final tries = [...membres]..sort((a, b) {
      final da = DateTime.tryParse('${a['joinedAt']}') ?? DateTime(1970);
      final db = DateTime.tryParse('${b['joinedAt']}') ?? DateTime(1970);
      return da.compareTo(db);
    });
  return tries.isNotEmpty && tries.first['id'] == userId;
}

/// Versions par charge « trousseau » (chapitre 38) — jumeau du web.
///
/// 🔴 PAS DE LIMITE AU NOMBRE DE CLÉS (décision du user, 10/10/2026) : une
/// enveloppe ne dépasse pas 64 Ko, un trousseau entier y tenait jusqu'à ~560
/// versions. On le DÉCOUPE ; chaque morceau est un trousseau valide, fusionné
/// à la réception.
const versionsParCharge = 400;

/// Découpe les versions en morceaux de [taille], dans l'ordre.
List<List<g.VersionCle>> decouperVersions(List<g.VersionCle> versions,
    [int taille = versionsParCharge]) {
  final tries = [...versions]..sort((a, b) => a.n.compareTo(b.n));
  return [
    for (var i = 0; i < tries.length; i += taille)
      tries.sublist(i, min(i + taille, tries.length)),
  ];
}

/// Le bilan d'une distribution de trousseau.
typedef BilanDistribution = ({int appareils, List<String> sansAppareil, List<String> echecs});

class GroupeChiffre {
  GroupeChiffre(this._service, this._api, this._monDeviceId, this._monCompte)
      : copies = CopiesTrousseau(_service.coffre, _api, _monCompte);

  /// Ma copie personnelle de chaque trousseau (lot 6).
  final CopiesTrousseau copies;

  final E2eeService _service;
  final Future<Map<String, dynamic>> Function(
    String methode,
    String chemin,
    Map<String, dynamic>? corps,
  ) _api;
  final Future<int> Function() _monDeviceId;
  final String? _monCompte;

  /* ══════════════ LE TROUSSEAU LOCAL ══════════════ */

  /// Les versions connues de ce groupe, de la plus ancienne à la plus récente.
  Future<List<g.VersionCle>> trousseau(String convId) async {
    final rangees = await _service.coffre.trousseauGroupe(convId);
    return [
      for (final v in rangees)
        g.VersionCle(
          n: v['n'] as int,
          cle: Uint8List.fromList(base64.decode(v['cle'] as String)),
          creeLe: v['creeLe'] as int,
        ),
    ]..sort((a, b) => a.n.compareTo(b.n));
  }

  /// Ajoute des versions. ⚠️ `fusionnerTrousseau` REFUSE de remplacer une clé
  /// connue : un faux trousseau ne peut ni rendre illisible ce qu'on lit, ni
  /// faire accepter une clé détenue par un autre sous un numéro existant.
  ///
  /// 🔴 LA COPIE PERSONNELLE SUIT CHAQUE CHANGEMENT (lot 6, chapitre 35) : une
  /// version reçue et pas recopiée serait perdue au changement de téléphone.
  Future<List<g.VersionCle>> ranger(
    String convId,
    List<g.VersionCle> recues, {
    bool deposerCopie = true,
  }) async {
    final connues = await trousseau(convId);
    final fusion = g.fusionnerTrousseau(connues, recues);
    if (fusion.length == connues.length) return fusion;
    await _service.coffre.rangerTrousseauGroupe(convId, [
      for (final v in fusion) {'n': v.n, 'cle': base64.encode(v.cle), 'creeLe': v.creeLe},
    ]);
    if (deposerCopie) unawaited(copies.deposer(convId, fusion));
    return fusion;
  }

  /// Dernière tentative de restauration, par groupe — pour ne pas boucler.
  final _restaurations = <String, DateTime>{};

  /// Le trousseau local, COMPLÉTÉ PAR MA COPIE quand il manque quelque chose
  /// (lot 6) : rien du tout (nouveau téléphone), ou la version [voulue].
  ///
  /// ⚠️ UNE TENTATIVE PAR GROUPE ET PAR DEMI-MINUTE. Jumeau du web.
  Future<List<g.VersionCle>> trousseauAvecRepli(String convId, [int? voulue]) async {
    final local = await trousseau(convId);
    final manque = local.isEmpty || (voulue != null && !local.any((v) => v.n == voulue));
    if (!manque) return local;
    final derniere = _restaurations[convId];
    if (derniere != null && DateTime.now().difference(derniere).inSeconds < 30) return local;
    _restaurations[convId] = DateTime.now();
    try {
      final copie = await copies.lire(convId);
      final repris = copie == null ? local : await ranger(convId, copie, deposerCopie: false);
      final encoreManquant =
          repris.isEmpty || (voulue != null && !repris.any((v) => v.n == voulue));
      // 🔴 LE REPLI « APPAREIL » (chapitre 37) : pas de copie, ou une copie en
      // retard. On demande à MES AUTRES appareils. Jumeau du web.
      if (encoreManquant) unawaited(demanderAMesAppareils(convId));
      return repris;
    } catch (_) {
      unawaited(demanderAMesAppareils(convId));
      return local;
    }
  }

  /* ══════════════ LE REPLI « APPAREIL » ══════════════ */

  final _demandes = <String, DateTime>{};
  final _reponses = <String, DateTime>{};

  /// Demande le trousseau de ce groupe à MES AUTRES appareils ET AUX
  /// ADMINISTRATEURS du groupe (hors fil). Jumeau du web.
  ///
  /// 🐛 POURQUOI AUSSI LES ADMINISTRATEURS (10/10/2026, constaté par le user) :
  /// un téléphone resté sur l'ancienne application à l'activation avait rangé
  /// la clé comme un message — perdue. Ses autres appareils, anciens, ne
  /// répondaient pas. Les administrateurs ont la clé, et peuvent la renvoyer
  /// à un membre qui l'a perdue.
  ///
  /// ⚠️ UNE DEMANDE PAR GROUPE ET PAR MINUTE. Ne lève jamais.
  Future<bool> demanderAMesAppareils(String convId) async {
    final moi = _monCompte;
    if (moi == null) return false;
    final derniere = _demandes[convId];
    if (derniere != null && DateTime.now().difference(derniere).inSeconds < 60) return false;
    _demandes[convId] = DateTime.now();
    try {
      final monAppareil = await _monDeviceId();
      final demande = g.ecrireDemandeTrousseau(convId);
      final enveloppes = <Map<String, dynamic>>[];
      Future<void> pour(String uid, List<int> appareils) async {
        for (final d in appareils) {
          final e = await _service.chiffrer(uid, d, demande);
          enveloppes.add({'destinataireId': uid, 'destinataireDevice': d, 'type': e.type, 'corps': e.corps});
        }
      }

      await pour(moi, await _service.ouvrirSessions(moi, exclure: monAppareil));
      final membres = await _membres(convId);
      for (final m in membres) {
        final uid = m['id'] as String;
        if (uid == moi || !estAdministrateur(membres, uid)) continue;
        try {
          await pour(uid, await _service.ouvrirSessions(uid));
        } catch (_) {
          // Un administrateur injoignable n'empêche pas de demander aux autres.
        }
      }
      if (enveloppes.isEmpty) return false;
      await _api('POST', '/api/e2ee/enveloppes',
          {'convId': convId, 'deviceId': monAppareil, 'enveloppes': enveloppes});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Quelqu'un me demande le trousseau d'un groupe. Je le lui envoie si c'est
  /// un de MES appareils (motif APPAREIL), ou si je suis ADMINISTRATEUR et lui
  /// MEMBRE ACTIF (motif AJOUT — ce que j'aurais fait en l'ajoutant).
  ///
  /// 🔴 L'expéditeur est sûr — c'est sa session Signal qui a déchiffré. Un
  /// simple membre ne répond qu'à ses propres appareils ; un ancien membre
  /// n'obtient rien. ⚠️ Une réponse par demandeur, groupe et demi-minute.
  Future<bool> repondreADemande(String convIdEnveloppe, String expediteurId, String clair) async {
    final moi = _monCompte;
    final convId = g.lireDemandeTrousseau(clair, convIdEnveloppe);
    if (expediteurId != moi) {
      final membres = await _membres(convId);
      if (moi == null || !estAdministrateur(membres, moi)) {
        throw const g.GroupeInvalide(
            "demande de trousseau d'un autre compte, et je n'administre pas le groupe");
      }
      if (!membres.any((m) => m['id'] == expediteurId)) {
        throw const g.GroupeInvalide("demande de trousseau d'un compte qui n'est pas membre");
      }
    }
    final versions = await trousseau(convId);
    if (versions.isEmpty) return false;
    final cle = '$convId:$expediteurId';
    final derniere = _reponses[cle];
    if (derniere != null && DateTime.now().difference(derniere).inSeconds < 30) return false;
    _reponses[cle] = DateTime.now();
    await distribuer(convId, expediteurId == moi ? 'APPAREIL' : 'AJOUT', versions, [expediteurId]);
    return true;
  }

  /// Nouveau téléphone : reprend TOUTES mes copies (archive ouverte). Rend le
  /// nombre de groupes repris. Ne lève jamais.
  Future<int> restaurerTous() async {
    var n = 0;
    try {
      for (final e in (await copies.lireToutes()).entries) {
        try {
          await ranger(e.key, e.value, deposerCopie: false);
          n++;
        } catch (_) {}
      }
    } catch (_) {}
    return n;
  }

  /// Parti ou exclu : on oublie la clé. Les messages déjà lus restent dans le
  /// cache (décision du user).
  Future<void> oublier(String convId) => _service.coffre.oublierTrousseauGroupe(convId);

  /* ══════════════ ENVOYER ══════════════ */

  Future<({Uint8List priv, Uint8List pub})> _maPaire() async {
    final paire = await _service.coffre.identiteLocale();
    return (
      priv: Uint8List.fromList(paire.getPrivateKey().serialize()),
      pub: Uint8List.fromList(paire.getPublicKey().publicKey.serialize()),
    );
  }

  /// Envoie un message dans un groupe chiffré : texte, fiche ou média.
  ///
  /// 1. l'appareil tire l'identifiant du message (il est signé dans le chiffré) ;
  /// 2. il chiffre la charge v2 avec la version la PLUS RÉCENTE qu'il connaît ;
  /// 3. un seul envoi : la ligne et son chiffré.
  ///
  /// ⚠️ `VERSION_PERIMEE` : la clé a changé et le nouveau trousseau n'est pas
  /// encore là. Le message ne part pas — surtout pas avec l'ancienne clé, que
  /// l'exclu connaît —, et on le dit ([CleGroupeAbsente]).
  Future<String> envoyer({
    required String convId,
    required String texte,
    String type = 'TEXT',
    String? replyToId,
    DescripteurMedia? media,
    bool vueUnique = false,
  }) async {
    final versions = await trousseauAvecRepli(convId);
    if (versions.isEmpty) throw const CleGroupeAbsente();
    final courante = versions.last;
    final moi = _monCompte;
    if (moi == null) throw StateError('Compte inconnu');
    final id = uuidV4();
    final appareil = await _monDeviceId();
    final genre = (type == 'CONTACT' || type == 'LOCATION') ? type : null;
    final charge = ecrireCharge(id, texte, media, replyToId, genre);
    final corps = g.chiffrerMessageGroupe(
      charge,
      courante.cle,
      g.ContexteGroupe(
          convId: convId, messageId: id, version: courante.n, expediteurId: moi, deviceId: appareil),
      (await _maPaire()).priv,
    );
    try {
      final r = await _api('POST', '/api/conversations/$convId/messages', {
        'id': id,
        'type': type,
        'chiffre': true,
        if (media != null) 'mediaIds': [media.id],
        if (replyToId != null) 'replyToId': replyToId,
        if (vueUnique) 'vueUnique': true,
        'groupe': {'version': courante.n, 'appareil': appareil, 'corps': corps},
      });
      return r['id'] as String;
    } on ApiException catch (e) {
      if (e.code == 'VERSION_PERIMEE') throw const CleGroupeAbsente();
      rethrow;
    }
  }

  /// Modifie un message : un NOUVEAU chiffré remplace l'ancien, avec la
  /// version courante (le serveur l'exige). Rend la date de modification.
  Future<DateTime?> modifier({
    required String convId,
    required String messageId,
    required String texte,
  }) async {
    final versions = await trousseauAvecRepli(convId);
    if (versions.isEmpty) throw const CleGroupeAbsente();
    final courante = versions.last;
    final moi = _monCompte;
    if (moi == null) throw StateError('Compte inconnu');
    final appareil = await _monDeviceId();
    final charge = ecrireCharge(messageId, texte, null, null, null, true);
    final corps = g.chiffrerMessageGroupe(
      charge,
      courante.cle,
      g.ContexteGroupe(
          convId: convId,
          messageId: messageId,
          version: courante.n,
          expediteurId: moi,
          deviceId: appareil),
      (await _maPaire()).priv,
    );
    try {
      final r = await _api('PATCH', '/api/conversations/$convId/messages/$messageId', {
        'chiffre': true,
        'groupe': {'version': courante.n, 'appareil': appareil, 'corps': corps},
      });
      return DateTime.tryParse('${r['editedAt']}');
    } on ApiException catch (e) {
      if (e.code == 'VERSION_PERIMEE') throw const CleGroupeAbsente();
      rethrow;
    }
  }

  /* ══════════════ LIRE ══════════════ */

  /// La clé d'identité de l'appareil qui a signé.
  ///
  /// ⚠️ D'ABORD CELLE QU'ON CONNAÎT DÉJÀ. Inconnue — un membre à qui l'on n'a
  /// jamais écrit —, on ouvre une session à deux avec ses appareils : le
  /// chemin ordinaire, qui vérifie les pré-clés signées et retient
  /// l'identité. On ne prend JAMAIS une clé servie juste pour l'occasion.
  Future<Uint8List?> _cleSignataire(String userId, int deviceId) async {
    final moi = _monCompte;
    final monAppareil = await _monDeviceId();
    if (userId == moi && deviceId == monAppareil) return (await _maPaire()).pub;
    Future<Uint8List?> connue() async {
      final id = await _service.coffre.getIdentity(SignalProtocolAddress(userId, deviceId));
      return id == null ? null : Uint8List.fromList(id.publicKey.serialize());
    }

    final deja = await connue();
    if (deja != null) return deja;
    try {
      await _service.ouvrirSessions(userId, exclure: userId == moi ? monAppareil : null);
    } catch (_) {
      return null;
    }
    return connue();
  }

  /// Ouvre un message de groupe : signature d'abord, déchiffrement ensuite,
  /// charge v2 vérifiée (elle doit annoncer CE message).
  ///
  /// [chiffre] : `{version, expediteurAppareil, corps}` tel que le serveur le
  /// rend avec chaque message.
  Future<(ClairGroupe?, EchecGroupe?)> lire({
    required String convId,
    required String messageId,
    required String expediteurId,
    required Map<String, dynamic> chiffre,
  }) async {
    final version = chiffre['version'] as int;
    final appareil = chiffre['expediteurAppareil'] as int;
    final versions = await trousseauAvecRepli(convId, version);
    final cle = versions.where((v) => v.n == version).firstOrNull;
    if (cle == null) return (null, EchecGroupe.cleAbsente);
    final signataire = await _cleSignataire(expediteurId, appareil);
    if (signataire == null) return (null, EchecGroupe.expediteurInconnu);
    try {
      final clair = g.dechiffrerMessageGroupe(
        chiffre['corps'] as String,
        cle.cle,
        g.ContexteGroupe(
            convId: convId,
            messageId: messageId,
            version: version,
            expediteurId: expediteurId,
            deviceId: appareil),
        signataire,
      );
      final c = lireCharge(clair, messageId);
      return (
        (texte: c.texte, media: c.media, reponseA: c.reponseA, genre: c.genre, modifie: c.modifie),
        null,
      );
    } catch (_) {
      return (null, EchecGroupe.invalide);
    }
  }

  /* ══════════════ RECEVOIR UN TROUSSEAU ══════════════ */

  /// Un trousseau arrivé dans une enveloppe hors fil.
  ///
  /// 🔴 TROIS CONTRÔLES (conception § 2.3) : le groupe écrit DANS le chiffré
  /// est celui de l'enveloppe ; l'expéditeur est ADMINISTRATEUR du groupe, ou
  /// MOI (mes autres appareils) ; aucune version connue n'est remplacée.
  ///
  /// ⚠️ LE RÔLE VIENT DU SERVEUR — limite assumée du chapitre 31.
  ///
  /// Lève [g.GroupeInvalide] si le trousseau est refusé.
  Future<List<g.VersionCle>> recevoirTrousseau(
    String convIdEnveloppe,
    String expediteurId,
    String clair,
  ) async {
    final t = g.lireChargeTrousseau(clair, convIdEnveloppe);
    if (expediteurId != _monCompte) {
      final r = await _api('GET', '/api/conversations/${t.convId}/members', null);
      final membres = ((r['members'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!estAdministrateur(membres, expediteurId)) {
        throw const g.GroupeInvalide(
            "trousseau envoyé par quelqu'un qui n'administre pas le groupe");
      }
    }
    return ranger(t.convId, t.versions);
  }

  /* ══════════════ LES GESTES D'ADMINISTRATEUR (lot 5) ══════════════ */

  /// Envoie un trousseau, hors fil, à chaque appareil de [destinataires] —
  /// moi compris (mes AUTRES appareils ; celui-ci est exclu).
  ///
  /// ⚠️ UN MEMBRE INJOIGNABLE N'ARRÊTE PAS LES AUTRES : il est compté.
  Future<BilanDistribution> distribuer(
    String convId,
    String motif,
    List<g.VersionCle> versions,
    Iterable<String> destinataires,
  ) async {
    final moi = _monCompte;
    final monAppareil = await _monDeviceId();
    final charges = [
      for (final morceau in decouperVersions(versions))
        g.ecrireChargeTrousseau(g.Trousseau(convId: convId, motif: motif, versions: morceau)),
    ];
    final enveloppes = <Map<String, dynamic>>[];
    final sansAppareil = <String>[];
    final echecs = <String>[];
    for (final uid in destinataires.toSet()) {
      try {
        final appareils =
            await _service.ouvrirSessions(uid, exclure: uid == moi ? monAppareil : null);
        if (appareils.isEmpty) {
          if (uid != moi) sansAppareil.add(uid);
          continue;
        }
        for (final charge in charges) {
          for (final d in appareils) {
            final e = await _service.chiffrer(uid, d, charge);
            enveloppes.add(
                {'destinataireId': uid, 'destinataireDevice': d, 'type': e.type, 'corps': e.corps});
          }
        }
      } catch (_) {
        echecs.add(uid);
      }
    }
    // Plafond d'un dépôt côté serveur : 1 000.
    for (var i = 0; i < enveloppes.length; i += 1000) {
      await _api('POST', '/api/e2ee/enveloppes', {
        'convId': convId,
        'deviceId': monAppareil,
        'enveloppes': enveloppes.sublist(i, min(i + 1000, enveloppes.length)),
      });
    }
    return (appareils: enveloppes.length, sansAppareil: sansAppareil, echecs: echecs);
  }

  Future<List<Map<String, dynamic>>> _membres(String convId) async {
    final r = await _api('GET', '/api/conversations/$convId/members', null);
    return ((r['members'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// ACTIVE le chiffrement d'un groupe (administrateur : le serveur vérifie).
  ///
  /// 🔴 LA CLÉ N'EST TIRÉE QU'APRÈS LA RÉSERVATION DU SERVEUR. Tirée avant puis
  /// refusée, elle resterait ici sous un numéro qui désigne, chez les autres,
  /// une AUTRE clé : la vraie serait refusée à sa réception. Jumeau du web.
  ///
  /// `deja` : quelqu'un l'avait déjà activé ; sa clé arrivera par la relève.
  Future<({bool deja, BilanDistribution? bilan})> activer(String convId) async {
    final r = await _api('POST', '/api/conversations/$convId/e2ee', {'appareil': await _monDeviceId()});
    if (r['deja'] == true) return (deja: true, bilan: null);
    final v1 = g.VersionCle(n: 1, cle: g.genererCleGroupe(), creeLe: DateTime.now().millisecondsSinceEpoch);
    final versions = await ranger(convId, [v1]);
    final bilan = await distribuer(
        convId, 'ACTIVATION', versions, (await _membres(convId)).map((m) => m['id'] as String));
    return (deja: false, bilan: bilan);
  }

  /// Le nouveau membre reçoit TOUT le trousseau : il lira l'historique
  /// (décision du user).
  Future<BilanDistribution> partagerAvecNouveaux(String convId, Iterable<String> userIds) async {
    final versions = await trousseauAvecRepli(convId);
    if (versions.isEmpty) throw const CleGroupeAbsente();
    return distribuer(convId, 'AJOUT', versions, userIds);
  }

  /// Après un ajout par numéro : retrouve les comptes ajoutés, et partage.
  Future<BilanDistribution> partagerApresAjout(String convId, List<String> numeros) async {
    final voulus = numeros.toSet();
    final ajoutes = (await _membres(convId))
        .where((m) => voulus.contains(m['publicNumber']))
        .map((m) => m['id'] as String);
    return partagerAvecNouveaux(convId, ajoutes);
  }

  /// Nouvelle version : après une EXCLUSION, ou sur demande (MANUEL).
  ///
  /// `null` si un autre administrateur l'a changée au même moment : sa clé
  /// arrive par la relève.
  Future<({int version, BilanDistribution bilan})?> changerCle(String convId, String motif) async {
    final etat = await _api('GET', '/api/conversations/$convId/e2ee', null);
    final attendue = ((etat['cleVersion'] as int?) ?? 0) + 1;
    try {
      await _api('POST', '/api/conversations/$convId/e2ee/versions',
          {'attendue': attendue, 'appareil': await _monDeviceId(), 'motif': motif});
    } on ApiException catch (e) {
      if (e.code == 'VERSION_CONFLIT') return null;
      rethrow;
    }
    final neuve =
        g.VersionCle(n: attendue, cle: g.genererCleGroupe(), creeLe: DateTime.now().millisecondsSinceEpoch);
    final versions = await ranger(convId, [...await trousseauAvecRepli(convId), neuve]);
    final bilan = await distribuer(
        convId, motif, versions, (await _membres(convId)).map((m) => m['id'] as String));
    return (version: attendue, bilan: bilan);
  }
}
