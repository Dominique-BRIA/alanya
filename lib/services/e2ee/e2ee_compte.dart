/// LA CLÉ DU COMPTE — chiffrement des groupes v2, lot 3 (11/11/2026).
/// Conception côté serveur : `docs/2026-11-11-e2ee-groupes-v2-conception.md`, § 3.1.
///
/// ⚠️ JUMEAU DE `STAGE-WEB/src/services/e2ee-compte.ts` (lot 4).
///
/// Une paire Curve25519 par COMPTE, et non par appareil : c'est elle qui
/// ouvre les emballages de groupe. Sa partie privée voyage chiffrée par la
/// clé maîtresse de l'archive (Argon2id sur le mot de passe) — le serveur la
/// garde sans pouvoir l'ouvrir — et dort en clair dans le coffre matériel de
/// chaque appareil connecté.
///
/// Le mot de passe, tapé à chaque connexion (tout le monde se connecte ainsi,
/// confirmé par le user le 11/11/2026), ouvre la clé maîtresse ; la clé
/// maîtresse ouvre la clé du compte ; la clé du compte ouvre tous les
/// groupes. Aucun autre appareil n'a besoin d'être en ligne.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' show Curve;

import '../../core/api_client.dart' show ApiException;
import 'e2ee_coffre.dart';
import 'e2ee_trousseau_perso.dart' show chiffrerCopie, dechiffrerCopie;

/// Ma clé de compte : publique 33 octets (format Signal), privée 32 octets.
class CleCompte {
  const CleCompte({required this.version, required this.pub, required this.priv});
  final int version;
  final Uint8List pub;
  final Uint8List priv;

  String get publiqueBase64 => base64.encode(pub);

  String versJson() => jsonEncode({
        'version': version,
        'pub': base64.encode(pub),
        'priv': base64.encode(priv),
      });

  static CleCompte? depuisJson(String? brut) {
    if (brut == null) return null;
    try {
      final m = jsonDecode(brut) as Map<String, dynamic>;
      return CleCompte(
        version: m['version'] as int,
        pub: Uint8List.fromList(base64.decode(m['pub'] as String)),
        priv: Uint8List.fromList(base64.decode(m['priv'] as String)),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Les données associées de la copie serveur de la partie privée : la clé
/// d'un compte ne peut pas être servie à un autre, ni sous une autre version.
Uint8List aadCleCompte(String compte, int version) =>
    Uint8List.fromList(utf8.encode('alanya-compte-v1\n$compte\n$version'));

typedef AppelApi = Future<Map<String, dynamic>> Function(
  String methode,
  String chemin,
  Map<String, dynamic>? corps,
);

class ComptesE2ee {
  ComptesE2ee(this._coffre, this._api, this._monCompte);

  final CoffreE2ee _coffre;
  final AppelApi _api;
  final String? _monCompte;

  CleCompte? _memoire;
  Future<CleCompte?>? _enCours;

  /// La clé de compte de cet appareil, sans réseau. `null` : pas encore là.
  Future<CleCompte?> locale() async =>
      _memoire ??= CleCompte.depuisJson(await _coffre.lireCleCompte());

  /// La clé de compte, à coup sûr si c'est possible :
  ///  1. celle du coffre de cet appareil ;
  ///  2. sinon celle du serveur, ouverte par la clé maîtresse ;
  ///  3. sinon une neuve, déposée sur le serveur (version 1).
  ///
  /// `null` quand la clé maîtresse manque (archive pas encore ouverte, ou
  /// refusée) : sans elle on ne peut ni ouvrir ni déposer une clé de compte.
  /// Les groupes continuent alors par l'ancien chemin (boîtes, copies).
  ///
  /// ⚠️ UNE SEULE DEMANDE À LA FOIS : la création ne doit pas avoir lieu deux
  /// fois en parallèle, deux clés différentes se disputeraient la version 1.
  Future<CleCompte?> assurer() async {
    final deja = await locale();
    if (deja != null) return deja;
    return _enCours ??= _assurer().whenComplete(() => _enCours = null);
  }

  Future<CleCompte?> _assurer() async {
    final moi = _monCompte;
    if (moi == null) return null;
    final maitresse = await _coffre.lireMaitresse();
    if (maitresse == null) return null;

    final r = await _api('GET', '/api/e2ee/compte', null);
    final serveur = r['cle'] as Map<String, dynamic>?;
    if (serveur != null) return _adopter(serveur, maitresse, moi);

    // Aucune clé : on en tire une, et on la dépose.
    final paire = Curve.generateKeyPair();
    final cle = CleCompte(
      version: 1,
      pub: Uint8List.fromList(paire.publicKey.serialize()),
      priv: Uint8List.fromList(paire.privateKey.serialize()),
    );
    try {
      await _api('PUT', '/api/e2ee/compte', {
        'version': cle.version,
        'publique': cle.publiqueBase64,
        'priveeChiffree':
            chiffrerCopie(maitresse, base64.encode(cle.priv), aadCleCompte(moi, cle.version)),
      });
    } on ApiException catch (e) {
      // Un autre de mes appareils l'a créée entre-temps : on prend la sienne.
      if (e.code == 'VERSION_COMPTE') {
        final relu = (await _api('GET', '/api/e2ee/compte', null))['cle'] as Map<String, dynamic>?;
        return relu == null ? null : _adopter(relu, maitresse, moi);
      }
      rethrow;
    }
    await _ranger(cle);
    return cle;
  }

  Future<CleCompte?> _adopter(Map<String, dynamic> serveur, Uint8List maitresse, String moi) async {
    final version = serveur['version'] as int;
    final priv = Uint8List.fromList(base64.decode(dechiffrerCopie(
      maitresse,
      serveur['priveeChiffree'] as String,
      aadCleCompte(moi, version),
    )));
    final cle = CleCompte(
      version: version,
      pub: Uint8List.fromList(base64.decode(serveur['publique'] as String)),
      priv: priv,
    );
    await _ranger(cle);
    return cle;
  }

  Future<void> _ranger(CleCompte cle) async {
    _memoire = cle;
    await _coffre.rangerCleCompte(cle.versJson());
  }

  /// Oublie la clé en mémoire (déconnexion : le coffre est vidé à part).
  void oublier() {
    _memoire = null;
  }
}
