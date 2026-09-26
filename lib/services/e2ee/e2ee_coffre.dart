/// LE COFFRE DES CLÉS, CÔTÉ MOBILE.
///
/// 🔴 LE MOBILE A ICI MIEUX QUE LE WEB. Le navigateur protège ses clés par un
/// `CryptoKey` non extractible ; le téléphone les met dans un coffre adossé au
/// MATÉRIEL — Android Keystore, iOS Keychain. Une copie du disque ne suffit pas
/// à les sortir.
///
/// ⚠️ `flutter_secure_storage` N'EST PAS UNE BASE DE DONNÉES. Il range de
/// petites valeurs, lentement. Les sessions Signal y vont parce qu'elles sont
/// petites et vitales ; le cache des messages n'y a PAS sa place.
///
/// ⚠️ CE QUI DISPARAÎT À LA DÉSINSTALLATION : sur Android le coffre part avec
/// l'application, sur iOS le trousseau peut survivre. On ne s'appuie donc sur
/// aucune des deux — l'archive chiffrée est ce qui rend l'appareil remplaçable.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// ⚠️ `encryptedSharedPreferences` RETIRÉ : Google a déprécié Jetpack Security
/// et le greffon migre tout seul. Le garder ne produisait qu un avertissement.
const _options = AndroidOptions();

/// Les magasins que la bibliothèque Signal exige, adossés au coffre matériel.
///
/// ⚠️ LES QUATRE MAGASINS SONT UN SEUL OBJET ici, contrairement à l'exemple de
/// la bibliothèque. Ils partagent le même coffre et la même clé de préfixe :
/// les séparer multiplierait les ouvertures sans rien isoler.
/// ⚠️ C EST `SignalProtocolStore` QU IL FAUT IMPLÉMENTER, pas les quatre
/// interfaces séparément : `SessionBuilder` et `SessionCipher` attendent le type
/// combiné, et lister les parents un par un ne le produit pas.
class CoffreE2ee implements SignalProtocolStore {
  CoffreE2ee(this._compte);

  final String _compte;
  final _magasin = const FlutterSecureStorage(aOptions: _options);

  String _cle(String suffixe) => 'e2ee/$_compte/$suffixe';

  Future<String?> _lire(String k) => _magasin.read(key: _cle(k));
  Future<void> _ecrire(String k, String v) =>
      _magasin.write(key: _cle(k), value: v);

  /* ══════════════ IDENTITÉ ══════════════ */

  /// Crée l'identité de cet appareil si elle n'existe pas encore.
  ///
  /// 🔴 UNE IDENTITÉ PAR APPAREIL, JAMAIS PAR COMPTE. C'est ce qui permet au
  /// téléphone et au navigateur d'exister en même temps : chacun a la sienne, et
  /// chacun reçoit sa propre enveloppe pour un message donné.
  Future<void> preparer() async {
    if (await _lire('identite') != null) return;

    final identite = generateIdentityKeyPair();
    await _ecrire('identite', base64.encode(identite.serialize()));
    await _ecrire('registrationId', '${generateRegistrationId(false)}');
  }

  Future<IdentityKeyPair> identiteLocale() async {
    final brut = await _lire('identite');
    if (brut == null) throw StateError('Identité absente — appeler preparer().');
    return IdentityKeyPair.fromSerialized(base64.decode(brut));
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() => identiteLocale();

  @override
  Future<int> getLocalRegistrationId() async =>
      int.parse((await _lire('registrationId'))!);

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final b = await _lire('identite.${address.toString()}');
    return b == null ? null : IdentityKey.fromBytes(base64.decode(b), 0);
  }

  /// Range la clé d'un correspondant, et dit si elle a CHANGÉ.
  ///
  /// 🔴 LE `true` EST CE QUI DÉCLENCHE L'AVERTISSEMENT À L'ÉCRAN. Un changement
  /// de clé est soit une réinstallation, soit une interposition — on ne peut pas
  /// les distinguer, donc on le dit sans bloquer, comme sur le web.
  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? id) async {
    if (id == null) return false;
    final k = 'identite.${address.toString()}';
    final avant = await _lire(k);
    final apres = base64.encode(id.serialize());
    await _ecrire(k, apres);
    return avant != null && avant != apres;
  }

  /// ⚠️ ON ACCEPTE TOUJOURS, ET ON AVERTIT AILLEURS. Refuser ici ferait échouer
  /// la réception sans que l'utilisateur comprenne pourquoi — décision reprise
  /// du web (modèle WhatsApp, 21/09/2026).
  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async =>
      true;


  /* ══════════════ L'IDENTIFIANT D'APPAREIL ══════════════ */

  /// Le numéro de CET appareil, stable pour toute la durée de l'installation.
  ///
  /// 🔴 IL DOIT SURVIVRE AUX REDÉMARRAGES. Le protocole adresse les enveloppes
  /// par (personne, appareil) : un numéro qui change à chaque lancement créerait
  /// une identité neuve à chaque fois, et le correspondant verrait un
  /// avertissement de changement de clé à chaque ouverture de l'application.
  ///
  /// ⚠️ TIRÉ AU SORT, PAS INCRÉMENTÉ. Le serveur ne distribue pas ces numéros ;
  /// deux appareils qui partiraient de 1 entreraient en collision sur le même
  /// compte, et les messages de l'un s'ouvriraient chez l'autre.
  Future<int> deviceId() async {
    final garde = await _lire('deviceId');
    if (garde != null) {
      final n = int.tryParse(garde);
      if (n != null && n > 0) return n;
    }
    // 1..2^31-1 : l'intervalle qu'accepte la colonne du serveur.
    final n = 1 + Random.secure().nextInt(2147483646);
    await _ecrire('deviceId', '$n');
    return n;
  }

  /* ══════════════ SESSIONS ══════════════ */

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final b = await _lire('session.${address.toString()}');
    return b == null
        ? SessionRecord()
        : SessionRecord.fromSerialized(base64.decode(b));
  }

  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) =>
      _ecrire('session.${address.toString()}', base64.encode(record.serialize()));

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _lire('session.${address.toString()}') != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _magasin.delete(key: _cle('session.${address.toString()}'));

  @override
  Future<void> deleteAllSessions(String name) async {
    final tout = await _magasin.readAll(aOptions: _options);
    for (final k in tout.keys) {
      if (k.startsWith(_cle('session.$name.'))) await _magasin.delete(key: k);
    }
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => const [];

  /* ══════════════ PRÉ-CLÉS ══════════════ */

  /// 🔴 TOUTES LES PRÉ-CLÉS DANS UNE SEULE ENTRÉE, et c'est un correctif de
  /// performance qui bloquait l'application.
  ///
  /// 🐛 Elles étaient rangées une par une : cinquante écritures dans le coffre
  /// sécurisé à chaque publication. Sur Android chaque écriture traverse le
  /// canal de plateforme et coûte plusieurs dizaines de millisecondes ; les
  /// enchaîner MONOPOLISAIT ce canal, et les lectures qui l'attendaient — dont
  /// celle du jeton de session — ne revenaient plus. L'écran de conversation
  /// restait en chargement infini.
  ///
  /// ⚠️ LE COFFRE SÉCURISÉ N'EST PAS UNE BASE DE DONNÉES. Il range quelques
  /// valeurs, lentement. Y faire des dizaines d'accès est un contresens d'usage,
  /// pas une simple lenteur.
  Future<Map<String, String>> _table(String nom) async {
    final brut = await _lire(nom);
    if (brut == null) return {};
    return (jsonDecode(brut) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
  }

  Future<void> _ecrireTable(String nom, Map<String, String> t) =>
      _ecrire(nom, jsonEncode(t));

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final b = (await _table('prekeys'))['$preKeyId'];
    if (b == null) throw InvalidKeyIdException('pré-clé $preKeyId absente');
    return PreKeyRecord.fromBuffer(base64.decode(b));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    final t = await _table('prekeys');
    t['$preKeyId'] = base64.encode(record.serialize());
    await _ecrireTable('prekeys', t);
  }

  /// Range tout un lot d'un coup — UNE seule écriture.
  Future<void> storePreKeys(List<PreKeyRecord> lot) async {
    final t = await _table('prekeys');
    for (final p in lot) {
      t['${p.id}'] = base64.encode(p.serialize());
    }
    await _ecrireTable('prekeys', t);
  }

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      (await _table('prekeys')).containsKey('$preKeyId');

  /// 🔴 UNE PRÉ-CLÉ NE SERT QU'UNE FOIS. La retirer après usage n'est pas du
  /// ménage : la réutiliser affaiblirait l'accord de clés du message suivant.
  @override
  Future<void> removePreKey(int preKeyId) async {
    final t = await _table('prekeys');
    t.remove('$preKeyId');
    await _ecrireTable('prekeys', t);
  }

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int id) async {
    final b = (await _table('signed'))['$id'];
    if (b == null) throw InvalidKeyIdException('pré-clé signée $id absente');
    return SignedPreKeyRecord.fromSerialized(base64.decode(b));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async =>
      (await _table('signed'))
          .values
          .map((v) => SignedPreKeyRecord.fromSerialized(base64.decode(v)))
          .toList();

  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) async {
    final t = await _table('signed');
    t['$id'] = base64.encode(record.serialize());
    await _ecrireTable('signed', t);
  }

  @override
  Future<bool> containsSignedPreKey(int id) async =>
      (await _table('signed')).containsKey('$id');

  @override
  Future<void> removeSignedPreKey(int id) async {
    final t = await _table('signed');
    t.remove('$id');
    await _ecrireTable('signed', t);
  }

  /// A-t-on déjà publié nos clés ?
  ///
  /// ⚠️ ON NE REPUBLIE PAS À CHAQUE LANCEMENT. L'identité ne change pas, et
  /// republier cinquante pré-clés à chaque ouverture coûte cher pour rien.
  Future<bool> dejaPublie() async => (await _lire('publie')) == '1';

  Future<void> noterPublie() => _ecrire('publie', '1');

  /* ══════════════ OUBLI ══════════════ */

  /// Efface tout — à la déconnexion.
  ///
  /// ⚠️ MÊME RÈGLE QUE SUR LE WEB : garder des clés privées après une
  /// déconnexion reviendrait à laisser sur l'appareil de quoi lire ce qui a été
  /// échangé, alors que se déconnecter veut dire le contraire.
  Future<void> oublier() async {
    final tout = await _magasin.readAll(aOptions: _options);
    for (final k in tout.keys) {
      if (k.startsWith('e2ee/$_compte/')) await _magasin.delete(key: k);
    }
  }
}
