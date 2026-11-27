/// LES CONTACTS DE RÉCUPÉRATION, CÔTÉ TÉLÉPHONE (27/11/2026, chantier 2).
///
/// 🔴 JUMEAU DE `STAGE-WEB/src/services/e2ee-contacts-recuperation.ts`.
///
/// Trois rôles :
///  - le PROPRIÉTAIRE choisit trois contacts : un secret neuf est posé comme
///    serrure « contacts », partagé en 2 sur 3, chaque part scellée pour la clé
///    de compte d'un contact ;
///  - le CONTACT ouvre sa part avec sa clé de compte et la rescelle pour la clé
///    éphémère de l'appareil qui demande — il ne voit jamais le secret ;
///  - l'APPAREIL QUI DEMANDE réunit deux parts, refait le secret, ouvre la
///    serrure « contacts » et refait la serrure « mot de passe ».
///
/// ⚠️ LA CLÉ PRIVÉE ÉPHÉMÈRE RESTE EN MÉMOIRE, comme pour le passage entre
/// appareils : rien n'est écrit hors du coffre.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' show Curve;

import '../../core/api_client.dart' show ApiException;
import 'e2ee_fournisseur.dart' show PileE2ee;
import 'e2ee_groupe.dart' show ContexteEmballage, deballerCle, emballerCle;
import 'e2ee_shamir.dart';

/// La part d'un contact, scellée pour sa clé de compte. Jumeau du web.
ContexteEmballage contextePart(String proprietaire, String contact, int generation, int versionCompte) =>
    ContexteEmballage(
      convId: 'recuperation:$proprietaire',
      destinataireId: contact,
      version: generation,
      versionCompte: versionCompte,
    );

/// La part rescellée pour l'appareil qui demande. Jumeau du web.
ContexteEmballage contexteAide(String demande, String proprietaire, int indice) =>
    ContexteEmballage(convId: 'contacts:$demande', destinataireId: proprietaire, version: indice, versionCompte: 1);

class MonContactRecuperation {
  const MonContactRecuperation(this.contactId, this.etat, this.nom);
  final String contactId;

  /// `invite`, `accepte`, `refuse`.
  final String etat;
  final String? nom;
}

class InvitationRecuperation {
  const InvitationRecuperation(this.id, this.nom);
  final String id;
  final String? nom;
}

class DemandeAide {
  const DemandeAide({
    required this.id,
    required this.ownerId,
    required this.nom,
    required this.clePublique,
    required this.generation,
    required this.indice,
    required this.part,
    required this.versionCompte,
  });

  final String id;
  final String ownerId;
  final String? nom;
  final String clePublique;
  final int generation;
  final int indice;
  final String part;
  final int versionCompte;

  static DemandeAide depuisJson(Map<String, dynamic> j) => DemandeAide(
        id: j['id'] as String,
        ownerId: j['ownerId'] as String,
        nom: j['nom'] as String?,
        clePublique: j['clePublique'] as String,
        generation: j['generation'] as int,
        indice: j['indice'] as int,
        part: j['part'] as String,
        versionCompte: j['versionCompte'] as int,
      );
}

/// Ce qu'a donné la relecture de MA demande d'aide.
enum IssueAide { aucune, attente, recue, refusee, expiree, echec }

class ContactsRecuperation {
  ContactsRecuperation(this._pile);

  final PileE2ee _pile;

  /// Ma demande d'aide en cours (identifiant, clé privée éphémère) — en mémoire.
  static ({String id, Uint8List priv})? _demande;

  /// Le nombre d'accords lu en dernier, pour l'écran.
  static int accordsLus = 0;

  Future<Map<String, dynamic>> _api(String m, String chemin, [Map<String, dynamic>? corps]) =>
      _pile.sauvegarde.api(m, chemin, corps);

  /* ══════════════ LE PROPRIÉTAIRE ══════════════ */

  Future<({int generation, bool actif, List<MonContactRecuperation> contacts})> mesContacts() async {
    final r = await _api('GET', '/api/e2ee/contacts-recuperation');
    return (
      generation: (r['generation'] as int?) ?? 0,
      actif: r['actif'] == true,
      contacts: (r['contacts'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map((c) => MonContactRecuperation(c['contactId'] as String, c['etat'] as String, c['nom'] as String?))
          .toList(),
    );
  }

  /// Les comptes qui ont une clé de compte (seuls eux peuvent recevoir une part).
  Future<Map<String, ({int version, String publique})>> clesDeCompte(List<String> ids) async {
    if (ids.isEmpty) return {};
    final r = await _api('GET', '/api/e2ee/cles-compte?ids=${Uri.encodeQueryComponent(ids.join(','))}');
    return {
      for (final c in (r['cles'] as List? ?? const []).cast<Map<String, dynamic>>())
        c['userId'] as String: (version: c['version'] as int, publique: c['publique'] as String),
    };
  }

  /// Confie la récupération à trois contacts. LÈVE en cas d'échec.
  ///
  /// ⚠️ LA SERRURE D'ABORD, LES PARTS ENSUITE : le serveur refuse des parts
  /// sans serrure « contacts ». Les parts d'avant n'ouvrent plus rien.
  Future<void> confier(List<String> contactIds) async {
    final moi = _pile.compteId;
    if (contactIds.length != 3) throw StateError('trois contacts');
    final cles = await clesDeCompte(contactIds);
    if (contactIds.any((id) => !cles.containsKey(id))) throw StateError('clé de compte manquante');
    final generation = (await mesContacts()).generation + 1;

    final r = Random.secure();
    final secret = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    if (!await _pile.sauvegarde.poserSerrureContacts(base64.encode(secret), moi)) {
      throw StateError('serrure non posée');
    }
    final parts = partagerSecret(secret, 3, 2);
    final corps = [
      for (var i = 0; i < 3; i++)
        {
          'contactId': contactIds[i],
          'indice': parts[i].indice,
          'versionCompte': cles[contactIds[i]]!.version,
          'part': emballerCle(
            parts[i].valeur,
            base64.decode(cles[contactIds[i]]!.publique),
            contextePart(moi, contactIds[i], generation, cles[contactIds[i]]!.version),
          ),
        },
    ];
    secret.fillRange(0, secret.length, 0);
    await _api('PUT', '/api/e2ee/contacts-recuperation', {'generation': generation, 'parts': corps});
  }

  Future<void> retirer() => _api('DELETE', '/api/e2ee/contacts-recuperation');

  /* ══════════════ LE CONTACT ══════════════ */

  Future<({List<InvitationRecuperation> invitations, List<DemandeAide> demandes})> aTraiter() async {
    try {
      final r = await _api('GET', '/api/e2ee/contacts-recuperation/a-traiter');
      return (
        invitations: (r['invitations'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((i) => InvitationRecuperation(i['id'] as String, i['nom'] as String?))
            .toList(),
        demandes: (r['demandes'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DemandeAide.depuisJson)
            .toList(),
      );
    } catch (_) {
      return (invitations: <InvitationRecuperation>[], demandes: <DemandeAide>[]);
    }
  }

  Future<bool> repondreInvitation(String id, bool accepte) async {
    try {
      await _api('POST', '/api/e2ee/contacts-recuperation/invitations/${Uri.encodeComponent(id)}',
          {'accepte': accepte});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// J'aide : ma part, ouverte avec MA clé de compte, rescellée pour la clé
  /// éphémère de l'appareil qui demande. Je ne vois jamais le secret.
  Future<bool> aider(DemandeAide d) async {
    try {
      final cle = await _pile.fil.groupe.comptes.assurer();
      if (cle == null || cle.version != d.versionCompte) return false;
      final valeur = deballerCle(
        d.part,
        cle.priv,
        contextePart(d.ownerId, _pile.compteId, d.generation, d.versionCompte),
      );
      final enveloppe = emballerCle(valeur, base64.decode(d.clePublique), contexteAide(d.id, d.ownerId, d.indice));
      valeur.fillRange(0, valeur.length, 0);
      await _api('POST', '/api/e2ee/demandes-contacts/${Uri.encodeComponent(d.id)}/reponse',
          {'accord': true, 'enveloppe': enveloppe});
      return true;
    } catch (e) {
      debugPrint('[e2ee] aide non envoyée : $e');
      return false;
    }
  }

  Future<bool> refuserAide(DemandeAide d) async {
    try {
      await _api('POST', '/api/e2ee/demandes-contacts/${Uri.encodeComponent(d.id)}/reponse', {'accord': false});
      return true;
    } catch (_) {
      return false;
    }
  }

  /* ══════════════ L'APPAREIL QUI DEMANDE ══════════════ */

  bool get aideEnAttente => _demande != null;

  /// Demande l'aide des contacts. `(envoyee: true)`, ou la date jusqu'à
  /// laquelle attendre (`jusquA`), ou rien en cas d'échec.
  Future<({bool envoyee, DateTime? jusquA})> demander(String appareil) async {
    try {
      final paire = Curve.generateKeyPair();
      final r = await _api('POST', '/api/e2ee/demandes-contacts', {
        'appareil': appareil,
        'clePublique': base64.encode(paire.publicKey.serialize()),
      });
      _demande = (id: r['id'] as String, priv: Uint8List.fromList(paire.privateKey.serialize()));
      accordsLus = 0;
      return (envoyee: true, jusquA: null);
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        return (envoyee: false, jusquA: DateTime.tryParse((e.detail?['jusquA'] as String?) ?? ''));
      }
      return (envoyee: false, jusquA: null);
    } catch (_) {
      return (envoyee: false, jusquA: null);
    }
  }

  /// Relit la demande. Deux accords : les parts sont ouvertes, assemblées, la
  /// serrure « contacts » s'ouvre avec le secret, la serrure « mot de passe »
  /// est refaite si [motDePasse] est connu.
  Future<IssueAide> relire({String? motDePasse}) async {
    final d = _demande;
    if (d == null) return IssueAide.aucune;
    final moi = _pile.compteId;
    final Map<String, dynamic> r;
    try {
      r = await _api('GET', '/api/e2ee/demandes-contacts/${Uri.encodeComponent(d.id)}');
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        _demande = null;
        return IssueAide.aucune;
      }
      return IssueAide.attente;
    } catch (_) {
      return IssueAide.attente;
    }
    final etat = r['etat'] as String? ?? '';
    accordsLus = (r['accords'] as int?) ?? 0;
    final parts = r['parts'] as List?;
    if (etat == 'ouverte' && parts == null) return IssueAide.attente;
    _demande = null;
    if (etat != 'ouverte') return etat == 'refusee' ? IssueAide.refusee : IssueAide.expiree;
    try {
      final morceaux = parts!
          .cast<Map<String, dynamic>>()
          .map((p) => PartShamir(
                p['indice'] as int,
                deballerCle(p['enveloppe'] as String, d.priv, contexteAide(d.id, moi, p['indice'] as int)),
              ))
          .take(2)
          .toList();
      final secret = assemblerSecret(morceaux);
      final ok = await _pile.sauvegarde.ouvrirParContacts(
        base64.encode(secret),
        _pile.coffre,
        motDePasse: motDePasse,
        compte: moi,
      );
      secret.fillRange(0, secret.length, 0);
      if (!ok) return IssueAide.echec;
    } catch (_) {
      return IssueAide.echec;
    }
    try {
      await _api('POST', '/api/e2ee/demandes-contacts/${Uri.encodeComponent(d.id)}/fin', {});
    } catch (_) {}
    return IssueAide.recue;
  }
}
