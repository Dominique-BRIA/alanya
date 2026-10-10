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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show SignalProtocolAddress;

import '../../core/api_client.dart' show ApiException;
import 'e2ee_groupe.dart' as g;
import 'e2ee_media.dart';
import 'e2ee_service.dart';

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

class GroupeChiffre {
  GroupeChiffre(this._service, this._api, this._monDeviceId, this._monCompte);

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
  Future<List<g.VersionCle>> ranger(String convId, List<g.VersionCle> recues) async {
    final fusion = g.fusionnerTrousseau(await trousseau(convId), recues);
    await _service.coffre.rangerTrousseauGroupe(convId, [
      for (final v in fusion) {'n': v.n, 'cle': base64.encode(v.cle), 'creeLe': v.creeLe},
    ]);
    return fusion;
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
    final versions = await trousseau(convId);
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
    final versions = await trousseau(convId);
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
    final versions = await trousseau(convId);
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
}
