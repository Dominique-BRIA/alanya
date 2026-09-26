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

  /* ══════════════ LE RÉASSORT DES PRÉ-CLÉS ══════════════ */

  /// Les identifiants des pré-clés à usage unique encore en stock.
  ///
  /// 🔴 L'INVENTAIRE AVANT LE RÉASSORT. Chaque pré-clé ne sert qu'une fois et
  /// la bibliothèque supprime la sienne après usage : compter ce qui reste est
  /// le seul moyen de savoir combien en générer — sans jeter celles que des
  /// correspondants ont peut-être déjà retirées du serveur.
  Future<List<int>> idsPrekeysUniques() async {
    final tout = await _magasin.readAll(aOptions: _options);
    final prefixe = _cle('prekey.');
    final ids = <int>[];
    for (final k in tout.keys) {
      if (!k.startsWith(prefixe)) continue;
      final n = int.tryParse(k.substring(prefixe.length));
      if (n != null) ids.add(n);
    }
    return ids;
  }

  /// Le prochain identifiant de pré-clé à usage unique.
  ///
  /// 🔴 JAMAIS RÉUTILISÉ, MÊME APRÈS USAGE. Un identifiant recyclé avec une
  /// matière neuve rendrait indéchiffrable le message qu'un correspondant a
  /// préparé avec l'ancienne publique — c'est exactement ce que faisait la
  /// régénération `0..49` à chaque démarrage, et pourquoi elle est partie.
  Future<int> prochainIdPrekey() async =>
      int.tryParse(await _lire('nextPrekeyId') ?? '') ?? 0;

  Future<void> reglerProchainIdPrekey(int n) => _ecrire('nextPrekeyId', '$n');

  /// L'identifiant de LA pré-clé signée de cet appareil.
  ///
  /// 🔴 UNE SEULE, STABLE. La rotation périodique casserait les liasses déjà
  /// retirées par des correspondants qui n'ont pas encore écrit : on garde
  /// donc la même tant qu'elle existe — y compris le `0` des versions
  /// précédentes, réutilisé tel quel à la mise à jour.
  Future<int> idPrekeySignee() async {
    final rangees = await loadSignedPreKeys();
    if (rangees.isNotEmpty) {
      rangees.sort((a, b) => a.id.compareTo(b.id));
      return rangees.first.id;
    }
    final n = int.tryParse(await _lire('signedId') ?? '');
    if (n != null && n >= 0) return n;
    await _ecrire('signedId', '1');
    return 1;
  }

  /// Ce jeu de clés a-t-il déjà été publié ?
  ///
  /// 🔴 POSÉ APRÈS LE POST, JAMAIS AVANT. Un fanion posé avant l'envoi
  /// mentirait en cas de réseau coupé entre les deux — et le démarrage
  /// suivant croirait le serveur fourni alors qu'il ne l'est pas.
  Future<bool> aPublie() async => await _lire('publie') == '1';

  Future<void> noterPublication() => _ecrire('publie', '1');

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

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final b = await _lire('prekey.$preKeyId');
    if (b == null) throw InvalidKeyIdException('pré-clé $preKeyId absente');
    return PreKeyRecord.fromBuffer(base64.decode(b));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _ecrire('prekey.$preKeyId', base64.encode(record.serialize()));

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      await _lire('prekey.$preKeyId') != null;

  /// 🔴 UNE PRÉ-CLÉ NE SERT QU'UNE FOIS. La supprimer après usage n'est pas du
  /// ménage : la réutiliser affaiblirait l'accord de clés du message suivant.
  @override
  Future<void> removePreKey(int preKeyId) =>
      _magasin.delete(key: _cle('prekey.$preKeyId'));

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int id) async {
    final b = await _lire('signed.$id');
    if (b == null) throw InvalidKeyIdException('pré-clé signée $id absente');
    return SignedPreKeyRecord.fromSerialized(base64.decode(b));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final tout = await _magasin.readAll(aOptions: _options);
    return tout.entries
        .where((e) => e.key.startsWith(_cle('signed.')))
        .map((e) => SignedPreKeyRecord.fromSerialized(base64.decode(e.value)))
        .toList();
  }

  @override
  Future<void> storeSignedPreKey(int id, SignedPreKeyRecord record) =>
      _ecrire('signed.$id', base64.encode(record.serialize()));

  @override
  Future<bool> containsSignedPreKey(int id) async =>
      await _lire('signed.$id') != null;

  @override
  Future<void> removeSignedPreKey(int id) =>
      _magasin.delete(key: _cle('signed.$id'));

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
