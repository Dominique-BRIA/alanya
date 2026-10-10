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
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// ⚠️ `encryptedSharedPreferences` RETIRÉ : Google a déprécié Jetpack Security
/// et le greffon migre tout seul. Le garder ne produisait qu un avertissement.
///
/// 🔴 `resetOnError: false` — L'INVERSE DU CHOIX FAIT POUR LES JETONS, ET POUR
/// LA RAISON EXACTEMENT INVERSE.
///
/// La valeur par défaut est `true` : à la moindre erreur de déchiffrement, le
/// greffon VIDE le coffre et repart à neuf. Pour deux jetons, c'est la bonne
/// réponse — ils se refabriquent en tapant son mot de passe.
///
/// ⚠️ ICI RIEN NE SE REFABRIQUE. Ce coffre porte l'identité Signal de cet
/// appareil, ses pré-clés et la clé maîtresse de l'archive. Effacées, les
/// conversations déjà reçues deviennent DÉFINITIVEMENT indéchiffrables, et
/// le correspondant voit une identité changer sans comprendre pourquoi.
///
/// ⚠️ ET CE SERAIT SILENCIEUX. C'est ce qui rend le défaut grave : rien
/// n'avertirait, ni ici ni en face. Mieux vaut une erreur qui remonte — le
/// démarrage la rattrape et le chiffrement reste simplement indisponible.
///
/// 🔴 ET UN ESPACE DE NOM À NOUS, SANS QUOI `resetOnError: false` NOUS BLOQUE.
///
/// 🐛 Ce coffre partageait l'espace par défaut avec les jetons — donc avec
/// leurs données héritées d'`EncryptedSharedPreferences`. La migration de ces
/// données échouait (« Migration failed after algorithm change »), et comme on
/// refuse d'effacer en silence, CHAQUE lecture levait.
///
/// ⚠️ `preparer()` ÉCHOUAIT DONC AVANT TOUT APPEL RÉSEAU, et `demarrer()`
/// rattrapait sans rien dire : aucune clé publiée, aucune trace. Le serveur
/// répondait ensuite, à juste titre, « un participant n'a pas publié ses clés »
/// — et ce participant, c'était nous.
///
/// ⚠️ LES DEUX RÉGLAGES SE TIENNENT : refuser l'effacement n'est tenable que
/// dans un espace dont on maîtrise le contenu. Les mélanger revenait à laisser
/// les jetons décider du sort des clés Signal.
///
/// ⚠️ CE QUE LE CHANGEMENT D'ESPACE COÛTE, ET POURQUOI C'EST ACCEPTABLE : ce
/// qui était rangé sous l'ancien espace devient inaccessible. Or aucun téléphone
/// n'y avait d'identité Signal utilisable — la publication échouait depuis
/// toujours — et la clé maîtresse de l'archive se retrouve à la connexion par
/// la serrure du mot de passe. Il n'y a donc rien à perdre, et une panne
/// entière à éviter.
const _options = AndroidOptions(
  storageNamespace: 'alanya_e2ee',
  resetOnError: false,
);

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
  Future<void> _effacer(String k) => _magasin.delete(key: _cle(k));

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

  /// 🔴 L'ALERTE VIT DANS LE COFFRE, ET NON PLUS EN MÉMOIRE.
  ///
  /// Elle a vécu dans un `Set` de cette classe. Le raisonnement tenait : une
  /// alerte qui réapparaît à chaque ouverture cesse d'être lue.
  ///
  /// ⚠️ MAIS `isTrustedIdentity` REND TOUJOURS `true` : quand on détecte le
  /// changement, la nouvelle clé est DÉJÀ ÉCRITE. Rien ne pourra le redétecter
  /// ensuite. L'application fermée avant d'avoir ouvert la conversation, et
  /// l'avertissement était perdu POUR TOUJOURS — sur un téléphone, qui se
  /// ferme et se rouvre vingt fois par jour.
  ///
  /// 🔴 UNE SUBSTITUTION DE CLÉ RÉUSSIE POUVAIT DONC PASSER INAPERÇUE. C'est le
  /// seul signal capable de révéler une interposition.
  ///
  /// ⚠️ L'ACCUSÉ DE LECTURE CONCILIE LES DEUX : l'alerte persiste tant qu'elle
  /// n'a pas été vue, puis disparaît définitivement. Elle ne se répète jamais,
  /// et ne se perd jamais.
  static const _prefixeChangee = 'cle-changee.';

  /// La clé de ce correspondant a-t-elle changé sans qu'on l'ait dit ?
  Future<bool> cleAChange(String compte) async =>
      (await _lire('$_prefixeChangee$compte')) != null;

  /// L'utilisateur a pris acte. ⚠️ CELA NE VALIDE RIEN : seul un code de
  /// sécurité comparé de vive voix dirait que la nouvelle clé est la bonne.
  Future<void> oublierAvertissement(String compte) =>
      _effacer('$_prefixeChangee$compte');

  /// ⚠️ ON N'ÉCRASE PAS UNE ALERTE DÉJÀ POSÉE. Deux changements de suite sans
  /// que personne n'ait rien vu, ce n'est pas deux alertes : c'est la même, et
  /// c'est sa PREMIÈRE date qui renseigne.
  /// Cet appareil est-il un appareil DE PLUS chez un correspondant déjà connu ?
  ///
  /// 🐛 SEUL LE CHANGEMENT DE CLÉ D'UN APPAREIL DÉJÀ VU ÉTAIT SIGNALÉ. Un
  /// serveur qui voudrait lire les messages de Bob n'a pas besoin de changer sa
  /// clé : il lui AJOUTE un appareil dont il détient la clé privée, et l'on
  /// chiffre désormais aussi pour lui — sans alerte. Jumeau du web
  /// (`saveIdentity` de `e2ee-store.ts`), prouvé par `test/e2ee_releve_test.dart` ⑦.
  ///
  /// ⚠️ PAS AU PREMIER CONTACT (rien n'est ajouté à quoi que ce soit), et PAS
  /// POUR SOI : mes propres appareils s'ajoutent de mon fait (lot 5).
  ///
  /// ⚠️ UNE LISTE PAR CORRESPONDANT, tenue ici : le coffre sécurisé ne sait pas
  /// énumérer ses clés sans tout relire. On ne relit tout qu'UNE fois par
  /// correspondant, pour amorcer la liste d'une installation antérieure à ce
  /// correctif — sinon son premier appareil de plus passerait inaperçu.
  Future<bool> _appareilDePlus(SignalProtocolAddress address) async {
    final compte = address.getName();
    if (compte == _compte) return false;
    final cleListe = 'appareilsConnus.$compte';
    var connus = (jsonDecode(await _lire(cleListe) ?? 'null') as List?)
        ?.cast<int>()
        .toSet();
    if (connus == null) {
      final prefixe = _cle('identite.$compte.');
      connus = {
        for (final k in (await _magasin.readAll()).keys)
          if (k.startsWith(prefixe)) int.tryParse(k.substring(prefixe.length)) ?? -1,
      }..remove(-1);
    }
    final deviceId = address.getDeviceId();
    final dePlus = connus.isNotEmpty && !connus.contains(deviceId);
    connus.add(deviceId);
    await _ecrire(cleListe, jsonEncode(connus.toList()));
    return dePlus;
  }

  Future<void> _noterChangement(String compte) async {
    final k = '$_prefixeChangee$compte';
    if (await _lire(k) != null) return;
    await _ecrire(k, DateTime.now().toIso8601String());
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
    if (avant == null && await _appareilDePlus(address)) {
      await _noterChangement(address.getName());
    }
    await _ecrire(k, apres);
    final change = avant != null && avant != apres;
    /*
     * 🔴 ICI, ET NULLE PART AILLEURS. Une ligne plus haut, l'ancienne clé vient
     * d'être écrasée : ne pas le noter maintenant, c'est ne plus jamais pouvoir
     * le savoir.
     *
     * ⚠️ `getName()` REND LE COMPTE, PAS L'ADRESSE `compte.appareil` — c'est
     * de la personne qu'on parle à l'écran, et son numéro d'appareil ne lui
     * dirait rien.
     */
    if (change) await _noterChangement(address.getName());
    return change;
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
    // Une copie des clés : voir `oublier()`.
    for (final k in tout.keys.toList()) {
      if (k.startsWith(_cle('session.$name.'))) await _magasin.delete(key: k);
    }
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => const [];

  /// Le numéro d'appareil que nous avons ANNONCÉ la dernière fois.
  ///
  /// 🔴 IL EXISTE POUR RATTRAPER UNE ERREUR PASSÉE. Les enveloppes ont
  /// longtemps annoncé l'appareil `1` — une valeur par défaut que personne ne
  /// remplaçait — alors que l'identité était publiée sous un numéro tiré au
  /// sort. Le correspondant a donc rangé sa session sous `<compte>.1`.
  ///
  /// ⚠️ CORRIGER L'ANNONCE NE SUFFIT PAS, ET C'EST TOUT LE PROBLÈME. Nos
  /// messages suivants disent venir d'une adresse où le correspondant n'a
  /// AUCUNE session, et un message ordinaire ne peut pas en ouvrir une : seul
  /// un message de type 3 le fait. La conversation se bloquerait dans un sens,
  /// en silence, et pour toujours.
  Future<String?> lireAppareilAnnonce() => _lire('appareil.annonce');
  Future<void> noterAppareilAnnonce(int n) => _ecrire('appareil.annonce', '$n');

  /// Efface TOUTES les sessions, pour que les suivantes se rouvrent à neuf.
  ///
  /// ⚠️ ON NE PERD AUCUN MESSAGE DÉJÀ LU : le clair est déjà dans le cache et
  /// dans l'archive. Ce qu'on perd, c'est l'état du ratchet — et c'est
  /// précisément ce qu'on veut jeter.
  ///
  /// ⚠️ L'IDENTITÉ N'EST PAS TOUCHÉE. La recréer ferait apparaître un
  /// avertissement de changement de clé chez tous les correspondants — une
  /// alerte de sécurité pour une opération de maintenance.
  Future<int> effacerToutesLesSessions() async {
    final tout = await _magasin.readAll(aOptions: _options);
    final prefixe = _cle('session.');
    var n = 0;
    // Une copie des clés : voir `oublier()`.
    for (final k in tout.keys.toList()) {
      if (k.startsWith(prefixe)) {
        await _magasin.delete(key: k);
        n++;
      }
    }
    return n;
  }

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
  /// Réserve [n] identifiants de pré-clé consécutifs, jamais encore servis.
  ///
  /// 🐛 ILS ÉTAIENT TIRÉS AU SORT (1 à 100 000, lots de 50 consécutifs). Deux
  /// lots qui se chevauchent écrasent ici une clé privée pendant que le
  /// serveur, qui écarte les doublons, garde l'ANCIENNE clé publique : la
  /// session ouverte avec elle est indéchiffrable. Rare, silencieux,
  /// définitif. Même correctif que le web (`reserverIdentifiants`).
  ///
  /// ⚠️ AU PREMIER APPEL, LE COMPTEUR PART AU-DESSUS du plus grand numéro déjà
  /// rangé : une installation existante a publié des numéros au hasard.
  ///
  /// ⚠️ 0xFFFFFF EST LA BORNE DU PROTOCOLE ; on repart de 1 au-delà.
  Future<int> reserverIdentifiants(int n) async {
    const borne = 0xFFFFFF;
    var debut = int.tryParse(await _lire('prochainIdentifiant') ?? '');
    if (debut == null) {
      var plusGrand = 0;
      for (final t in ['prekeys', 'signed']) {
        for (final k in (await _table(t)).keys) {
          final v = int.tryParse(k);
          if (v != null && v > plusGrand) plusGrand = v;
        }
      }
      debut = plusGrand + 1;
    }
    if (debut + n > borne) debut = 1;
    await _ecrire('prochainIdentifiant', '${debut + n}');
    return debut;
  }

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

  /// Les fils que ce compte a vus chiffrés — voir `E2eeFil.noteEtat`.
  ///
  /// ⚠️ DANS LE COFFRE, DONC PAR COMPTE : `_cle` préfixe par le compte, et
  /// `oublier()` l'efface avec le reste.
  Future<Set<String>> filsChiffres() async {
    final brut = await _lire('fils-chiffres');
    if (brut == null) return <String>{};
    try {
      return (jsonDecode(brut) as List).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> memoriserFilsChiffres(Set<String> fils) =>
      _ecrire('fils-chiffres', jsonEncode(fils.toList()));

  /* ══════════════ LES TROUSSEAUX DE GROUPE (lot 3, chapitre 34) ══════════════ */

  /// Le trousseau d'un groupe chiffré : `[{n, cle (base64), creeLe}]`.
  ///
  /// ⚠️ DANS LE COFFRE MATÉRIEL, comme les clés Signal : ce sont des clés, et
  /// `oublier()` les efface avec le reste à la déconnexion.
  Future<List<Map<String, dynamic>>> trousseauGroupe(String convId) async {
    final brut = await _lire('groupe.cles.$convId');
    if (brut == null) return const [];
    try {
      return (jsonDecode(brut) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> rangerTrousseauGroupe(String convId, List<Map<String, dynamic>> versions) =>
      _ecrire('groupe.cles.$convId', jsonEncode(versions));

  /// On a quitté le groupe, ou on en a été exclu (décision du user : les
  /// messages déjà lus restent dans le cache).
  Future<void> oublierTrousseauGroupe(String convId) => _effacer('groupe.cles.$convId');


  /* ══════════════ LA CLÉ MAÎTRESSE DE L'ARCHIVE ══════════════ */

  /// Range la clé maîtresse de l'archive dans le coffre matériel.
  ///
  /// 🔴 C'EST CE QUI FERME LA BOUCLE. Une archive créée avec la seule clé de
  /// récupération ne pourrait plus s'ouvrir à la connexion suivante : il n'y a
  /// pas de serrure « mot de passe », et le mot de passe ne peut pas en poser
  /// une sans d'abord OUVRIR l'archive. En gardant la clé maîtresse ici, la
  /// connexion suivante l'ouvre directement et pose la serrure manquante.
  ///
  /// ⚠️ CE QUE CELA COÛTE, ET IL FAUT L'ASSUMER : le coffre contient déjà les
  /// clés Signal et le cache. Mais l'archive porte l'historique d'AVANT cet
  /// appareil — y ranger sa clé élargit ce qu'une compromission rapporte.
  ///
  /// ⚠️ CE QUI LE REND ACCEPTABLE : le coffre est adossé au MATÉRIEL, et
  /// `oublier()` le vide à la déconnexion — la clé part avec.
  Future<void> rangerMaitresse(Uint8List cle) =>
      _ecrire('archive.maitresse', base64.encode(cle));

  /// Combien de blocs d'archive ont déjà été repris sur cet appareil.
  ///
  /// ⚠️ UN NOMBRE, PAS UNE DATE. Les blocs ne se modifient jamais et ne se
  /// suppriment pas : leur nombre ne peut que croître, ce qui en fait un
  /// repère suffisant et impossible à fausser par une horloge déréglée.
  Future<String?> lireBlocsRepris() => _lire('archive.blocs');
  Future<void> noterBlocsRepris(int n) => _ecrire('archive.blocs', '$n');

  Future<Uint8List?> lireMaitresse() async {
    final b = await _lire('archive.maitresse');
    return b == null ? null : Uint8List.fromList(base64.decode(b));
  }

  /// Le secret de la serrure « trousseau » de CET appareil.
  ///
  /// ⚠️ IL NE QUITTE JAMAIS LE COFFRE MATÉRIEL, et notre serveur ne le voit
  /// jamais — contrairement au mot de passe, qu'il reçoit à chaque connexion.
  /// C'est ce qui fait de cette serrure la plus forte des trois face à un
  /// serveur compromis.
  Future<String?> lireSecretTrousseau() => _lire('trousseau.secret');
  Future<void> rangerSecretTrousseau(String s) =>
      _ecrire('trousseau.secret', s);

  /* ══════════════ OUBLI ══════════════ */

  /// Efface tout — à la déconnexion.
  ///
  /// ⚠️ MÊME RÈGLE QUE SUR LE WEB : garder des clés privées après une
  /// déconnexion reviendrait à laisser sur l'appareil de quoi lire ce qui a été
  /// échangé, alors que se déconnecter veut dire le contraire.
  Future<void> oublier() async {
    final tout = await _magasin.readAll(aOptions: _options);
    // ⚠️ UNE COPIE DES CLÉS : effacer en parcourant la table elle-même casse la
    // boucle dès que `readAll` rend la table vivante (le stockage simulé des
    // tests le fait) — et le coffre restait à moitié plein.
    for (final k in tout.keys.toList()) {
      if (k.startsWith('e2ee/$_compte/')) await _magasin.delete(key: k);
    }
  }
}
