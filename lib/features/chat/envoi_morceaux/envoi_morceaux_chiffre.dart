import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/api_client.dart';
import '../../../models/message.dart';
import '../../../services/e2ee/e2ee_apercus.dart';
import '../../../services/e2ee/e2ee_fil.dart';
import '../../../services/e2ee/e2ee_groupe_fil.dart' show uuidV4;
import '../../../services/e2ee/e2ee_media.dart';
import '../../../services/e2ee/e2ee_media_fichier.dart';
import '../../../widgets/media/media_picker_sheet.dart' show MediaPickResult;
import 'decoupage_morceaux.dart';
import 'envoi_morceaux_api.dart';
import 'transport_morceaux.dart';

/// ENVOYER UN MÉDIA CHIFFRÉ EN MORCEAUX, MÊME APPLICATION FERMÉE — lot 3
/// (cours, chapitre 44).
///
/// Le parcours, dans cet ordre :
///
///   1. l'APERÇU, tant que le fichier est en clair ;
///   2. le CHIFFREMENT, de fichier à fichier, dans un isolat (chapitre 43) ;
///   3. la RÉSERVATION : le serveur rend l'identifiant de l'envoi — qui sera
///      celui du média —, un jeton d'envoi, et le découpage ;
///   4. le DESCRIPTEUR, qui cite ce média ;
///   5. la PRÉPARATION du message (identifiant tiré, enveloppes ou chiffré de
///      groupe) et sa PROGRAMMATION chez le serveur (chapitre 42) ;
///   6. MA COPIE : cache, archive, clair ;
///   7. les MORCEAUX, confiés à Android d'un coup.
///
/// 🔴 TOUT CE QUI EST CRYPTOGRAPHIQUE SE PASSE AVANT L'ÉTAPE 7, AU PREMIER
/// PLAN. Ensuite, il ne reste que des octets opaques à pousser : Android peut
/// le faire application fermée, et le SERVEUR publie le message quand le
/// dernier morceau arrive. Personne n'a besoin du code Dart à la fin.
///
/// ⚠️ LE CHEMIN EN CLAIR (lot 4) passe par [SuiviEnvoisMorceaux.lancerFichier] :
/// mêmes morceaux, même reprise, mais pas de publication différée — le
/// serveur ne sait pas annoncer en temps réel un message en clair qu'il
/// créerait lui-même. C'est la file d'envoi (`EnvoiMediaStore`) qui poste le
/// message une fois le fichier arrivé.
class EnvoiMorceauxSuivi {
  EnvoiMorceauxSuivi({
    required this.reservation,
    required this.convId,
    required this.cheminRelatif,
    this.messageId,
    required List<Morceau> morceaux,
    this.message,
  }) : _progression = ProgressionEnvoi(morceaux);

  final ReservationEnvoi reservation;

  /// Conversation de l'envoi, quand on la connaît (vide pour un fichier en
  /// clair : c'est la file d'envoi qui la porte).
  final String convId;

  /// Le fichier envoyé, relatif aux documents de l'application.
  final String cheminRelatif;

  /// Le message publié par le serveur (chemin chiffré). Nul en clair.
  final String? messageId;

  /// Le message tel que le fil l'affichera une fois publié (ma copie). Nul
  /// pour un envoi REPRIS au démarrage : le fil le relira du serveur.
  final Message? message;

  final ProgressionEnvoi _progression;

  /// 0 à 0,99 pendant l'envoi ; 1 quand le serveur a assemblé.
  final ValueNotifier<double> progression = ValueNotifier(0);

  final Completer<EtatEnvoiServeur> _fin = Completer();

  /// Rend l'état final (publié, ou refusé à la publication). Lève si l'envoi
  /// a échoué pour de bon.
  Future<EtatEnvoiServeur> get fin => _fin.future;

  void _rafraichir() => progression.value = _progression.fraction;
}

/// Où vivent les fichiers chiffrés en attente, sous les DOCUMENTS de
/// l'application — jamais le cache, que le système vide quand l'espace manque,
/// c'est-à-dire au pire moment (même règle que `EnvoisPersistes`).
const dossierEnvoisMorceaux = 'envois_morceaux';

class SuiviEnvoisMorceaux {
  SuiviEnvoisMorceaux._();
  static final instance = SuiviEnvoisMorceaux._();

  EnvoiMorceauxApi? _api;
  TransportMorceaux? _transport;
  String? _racine;
  StreamSubscription<EvenementMorceau>? _abonnement;
  final _actifs = <String, EnvoiMorceauxSuivi>{};

  /// Branché (au démarrage, par `main`) : sans cela, l'écran garde l'envoi
  /// d'un seul bloc.
  bool get pret => _api != null;

  /// Les envois en cours d'une conversation : l'écran les remontre en bulles
  /// quand on y revient.
  Iterable<EnvoiMorceauxSuivi> enCoursPour(String convId) =>
      _actifs.values.where((s) => s.convId == convId);

  /// [racineDocuments] : le dossier des documents de l'application.
  void brancher({
    required EnvoiMorceauxApi api,
    required TransportMorceaux transport,
    required String racineDocuments,
  }) {
    _api = api;
    _transport = transport;
    _racine = racineDocuments;
    _abonnement?.cancel();
    _abonnement = transport.evenements.listen(_surEvenement);
  }

  /// Pour les tests.
  @visibleForTesting
  void debrancher() {
    _abonnement?.cancel();
    _abonnement = null;
    _api = null;
    _transport = null;
    _racine = null;
    _actifs.clear();
  }

  // ═══════════════════════ LANCER ═══════════════════════

  Future<EnvoiMorceauxSuivi> lancer({
    required E2eeFil fil,
    required String convId,
    /// `null` pour un GROUPE chiffré.
    required String? pairId,
    required MediaPickResult fichier,
    String legende = '',
    String? replyToId,
    bool vueUnique = false,
    /// MA COPIE du message : `EnvoiMediaChiffre.rangerMaCopie` dans
    /// l'application (cache local, archive, clair). Passée par l'appelant
    /// pour que le test, sans base locale, puisse jouer le reste pour de vrai.
    required Future<Message> Function(String messageId, DescripteurMedia d) rangerMaCopie,
    /// L'aperçu : [fabriquerApercu] par défaut.
    Future<Apercu> Function(MediaPickResult fichier)? apercu,
  }) async {
    final api = _api!, transport = _transport!, racine = _racine!;
    final mime = fichier.mimeType;

    // 1. Aperçu.
    final a = await (apercu ??
        (f) => fabriquerApercu(f.bytes, f.mimeType, chemin: f.path, dureeMs: f.durationMs))(fichier);

    // 2. Chiffrement vers un dossier PROVISOIRE : l'identifiant de l'envoi
    // n'existe pas encore (il faut la taille du chiffré pour réserver).
    final provisoire = '$racine/$dossierEnvoisMorceaux/prep-${uuidV4()}';
    final f = await chiffrerVersFichierHorsDuFil(
      destination: '$provisoire/chiffre.bin',
      // Le chemin évite de recopier tout le fichier vers l'isolat ; les
      // octets servent quand il n'y a pas de fichier (un vocal).
      source: _cheminUtilisable(fichier),
      octets: _cheminUtilisable(fichier) == null ? fichier.bytes : null,
    );

    ReservationEnvoi? r;
    try {
      // 3. Réservation.
      r = await api.reserver(
        taille: f.taille,
        empreinteHex: f.empreinteHex,
        durationMs: fichier.durationMs,
      );
      final dossier = '$dossierEnvoisMorceaux/${r.id}';
      await Directory(provisoire).rename('$racine/$dossier');

      // 4. Descripteur : il cite le média par l'identifiant de l'envoi.
      final d = DescripteurMedia(
        id: r.mediaId,
        cle: f.cle,
        empreinte: f.empreinteBase64,
        taille: f.tailleClair,
        mime: mime,
        nom: fichier.fileName,
        largeur: a.largeur,
        hauteur: a.hauteur,
        dureeMs: a.dureeMs,
        pages: a.pages,
        apercu: a.apercu,
      );

      // 5. Préparation (le cliquet avance ICI) et programmation.
      final publication = await fil.preparerMedia(
        convId: convId,
        pairId: pairId,
        media: d,
        legende: legende,
        replyToId: replyToId,
        vueUnique: vueUnique,
      );
      final messageId = publication['messageId'] as String;
      await api.programmer(r.id, publication);

      // 6. Ma copie.
      final message = await rangerMaCopie(messageId, d);

      // 7. Le registre, puis les morceaux.
      final morceaux = morceauxDe(f.taille, r.tailleMorceau);
      final suivi = EnvoiMorceauxSuivi(
        reservation: r,
        convId: convId,
        cheminRelatif: '$dossier/chiffre.bin',
        messageId: messageId,
        morceaux: morceaux,
        message: message,
      );
      await _ecrireRegistre(r,
          convId: convId, messageId: messageId, fichier: suivi.cheminRelatif);
      _actifs[r.id] = suivi;
      await transport.confier(r, suivi.cheminRelatif, morceaux, titre: _titre(mime));
      return suivi;
    } catch (_) {
      // Rien ne doit rester derrière un envoi qui n'a pas pu partir : ni le
      // chiffré sur le disque, ni la réservation chez le serveur.
      await _effacerDossier(provisoire);
      if (r != null) {
        await _effacerDossier('$racine/$dossierEnvoisMorceaux/${r.id}');
        unawaited(api.abandonner(r.id, r.jeton).catchError((_) {}));
        _actifs.remove(r.id);
      }
      rethrow;
    }
  }

  // ═══════════════════════ EN CLAIR (lot 4) ═══════════════════════

  /// Envoie EN MORCEAUX un fichier en clair déjà rangé sous les documents de
  /// l'application, à [cheminRelatif] — la file d'envoi le range dans
  /// `envois_en_attente/`, d'où Android l'enverra sans nouvelle copie.
  ///
  /// Rend le suivi dès que les morceaux sont confiés ; `fin` se termine quand
  /// le serveur a fait du fichier un média, dont l'identifiant est
  /// `reservation.mediaId`. Le MESSAGE reste à poster par l'appelant.
  Future<EnvoiMorceauxSuivi> lancerFichier({
    required String cheminRelatif,
    required String nom,
    required String mime,
    int? dureeMs,
  }) async {
    final api = _api!, transport = _transport!, racine = _racine!;
    final taille = await File('$racine/$cheminRelatif').length();
    final r = await api.reserver(
      taille: taille,
      chiffre: false,
      nom: nom,
      mime: mime,
      durationMs: dureeMs,
    );
    try {
      final morceaux = morceauxDe(taille, r.tailleMorceau);
      final suivi = EnvoiMorceauxSuivi(
        reservation: r,
        convId: '',
        cheminRelatif: cheminRelatif,
        morceaux: morceaux,
      );
      await Directory('$racine/$dossierEnvoisMorceaux/${r.id}').create(recursive: true);
      await _ecrireRegistre(r, convId: '', fichier: cheminRelatif);
      _actifs[r.id] = suivi;
      await transport.confier(r, cheminRelatif, morceaux, titre: _titre(mime));
      return suivi;
    } catch (_) {
      _actifs.remove(r.id);
      await _effacerDossier('$racine/$dossierEnvoisMorceaux/${r.id}');
      unawaited(api.abandonner(r.id, r.jeton).catchError((_) {}));
      rethrow;
    }
  }

  /// Le suivi d'un envoi CONNU par sa réservation — celle que la file d'envoi
  /// a gardée sur le disque. Après un redémarrage, c'est ainsi qu'elle
  /// retrouve un fichier à moitié parti au lieu de le renvoyer en entier.
  ///
  /// ⚠️ LE SERVEUR FAIT FOI : l'envoi est relu chez lui ; terminé, `fin` se
  /// termine aussitôt ; en cours, Android reçoit les morceaux qui manquent.
  EnvoiMorceauxSuivi suivre(ReservationEnvoi r, String cheminRelatif) {
    final deja = _actifs[r.id];
    if (deja != null) return deja;
    final s = EnvoiMorceauxSuivi(
      reservation: r,
      convId: '',
      cheminRelatif: cheminRelatif,
      morceaux: morceauxDe(_tailleDe(cheminRelatif), r.tailleMorceau),
    );
    _actifs[r.id] = s;
    unawaited(() async {
      await Directory('$_racine/$dossierEnvoisMorceaux/${r.id}').create(recursive: true);
      await _ecrireRegistre(r, convId: '', fichier: cheminRelatif);
      await _verifier(s, relire: true);
    }());
    return s;
  }

  /// L'utilisateur renonce : Android cesse d'envoyer, le serveur efface le
  /// fichier partiel.
  Future<void> abandonner(ReservationEnvoi r) async {
    final s = _actifs.remove(r.id);
    await _transport?.annuler(r.id);
    await _api?.abandonner(r.id, r.jeton).catchError((_) {});
    await _effacerDossier('$_racine/$dossierEnvoisMorceaux/${r.id}');
    if (s != null && !s._fin.isCompleted) {
      s._fin.completeError(StateError('envoi abandonné'));
    }
  }

  String? _cheminUtilisable(MediaPickResult f) {
    final p = f.path;
    if (p == null || p.isEmpty) return null;
    try {
      // Un chemin dont le contenu ne correspond plus aux octets (fichier
      // remplacé depuis la sélection) chiffrerait autre chose que l'aperçu.
      return File(p).lengthSync() == f.bytes.length ? p : null;
    } catch (_) {
      return null;
    }
  }

  static String _titre(String mime) {
    if (mime.startsWith('image/')) return 'Envoi d’une photo';
    if (mime.startsWith('video/')) return 'Envoi d’une vidéo';
    if (mime.startsWith('audio/')) return 'Envoi d’un audio';
    return 'Envoi d’un fichier';
  }

  // ═══════════════════════ SUIVRE ═══════════════════════

  void _surEvenement(EvenementMorceau e) {
    final s = _actifs[e.envoiId];
    if (s == null) return;
    switch (e) {
      case MorceauAvance(:final indice, :final fraction):
        s._progression.avancer(indice, fraction);
        s._rafraichir();
      case MorceauRecu(:final indice, :final reponse):
        s._progression.morceauRecu(indice);
        s._rafraichir();
        final etat = _lireEtat(reponse);
        if (etat != null && etat.termine) unawaited(_finir(s, etat));
      case MorceauEchoue():
        // Réessais épuisés : on demande au serveur où en est l'envoi plutôt
        // que de conclure — un autre morceau a peut-être tout terminé.
        unawaited(_verifier(s));
    }
  }

  EtatEnvoiServeur? _lireEtat(String? corps) {
    if (corps == null || corps.isEmpty) return null;
    try {
      final j = jsonDecode(corps);
      return j is Map<String, dynamic> ? EtatEnvoiServeur.depuisJson(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _verifier(EnvoiMorceauxSuivi s, {bool relire = false}) async {
    final api = _api;
    if (api == null) return;
    try {
      final etat = await api.etat(s.reservation.id, s.reservation.jeton);
      if (relire) {
        s._progression.dejaRecus(List<int>.generate(s.reservation.nbMorceaux, (i) => i)
            .where((i) => !etat.manquants.contains(i)));
        s._rafraichir();
      }
      if (etat.termine) return _finir(s, etat);
      // Tout est là mais l'assemblage n'a pas eu lieu : le filet.
      if (etat.manquants.isEmpty) {
        final apres = await api.terminer(s.reservation.id, s.reservation.jeton);
        if (apres.termine) return _finir(s, apres);
      }
      // Des morceaux manquent et Android ne les a plus : on les lui redonne.
      final enVol = await _transport!.enVol(s.reservation.id);
      final aRedonner = etat.manquants.where((i) => !enVol.contains(i)).toSet();
      if (aRedonner.isNotEmpty) {
        final tous = morceauxDe(_tailleDe(s.cheminRelatif), s.reservation.tailleMorceau);
        await _transport!.confier(
          s.reservation,
          s.cheminRelatif,
          tous.where((m) => aRedonner.contains(m.indice)).toList(),
          titre: 'Envoi d’un fichier',
        );
      }
    } on ApiException catch (e) {
      // L'envoi n'existe plus chez le serveur (expiré, abandonné) : il ne
      // reviendra pas. On le dit, et on efface.
      if (e.statusCode == 404 || e.statusCode == 410) {
        _actifs.remove(s.reservation.id);
        await _effacerDossier('$_racine/$dossierEnvoisMorceaux/${s.reservation.id}');
        if (!s._fin.isCompleted) s._fin.completeError(e);
      }
    } catch (_) {
      // Réseau : Android réessaiera, et la prochaine ouverture aussi.
    }
  }

  int _tailleDe(String cheminRelatif) {
    try {
      return File('$_racine/$cheminRelatif').lengthSync();
    } catch (_) {
      return 1;
    }
  }

  Future<void> _finir(EnvoiMorceauxSuivi s, EtatEnvoiServeur etat) async {
    if (s._fin.isCompleted) return;
    s._progression.terminer();
    s._rafraichir();
    _actifs.remove(s.reservation.id);
    // Le fichier est chez le serveur : la copie chiffrée locale ne sert plus
    // (le clair, lui, reste dans le cache des médias).
    await _effacerDossier('$_racine/$dossierEnvoisMorceaux/${s.reservation.id}');
    s._fin.complete(etat);
  }

  // ═══════════════════════ REPRENDRE ═══════════════════════

  /// Au démarrage (pile E2EE prête) : chaque envoi resté sur le disque est
  /// relu chez le serveur — terminé, on nettoie ; en cours, on redonne à
  /// Android les morceaux qu'il n'a plus.
  ///
  /// ⚠️ C'EST AUSSI LE NETTOYAGE. Application fermée, personne n'a vu le
  /// dernier morceau partir : le chiffré reste sur le disque jusqu'ici.
  Future<void> reprendre() async {
    final racine = _racine, api = _api;
    if (racine == null || api == null) return;
    final base = Directory('$racine/$dossierEnvoisMorceaux');
    if (!await base.exists()) return;
    await for (final entree in base.list()) {
      if (entree is! Directory) continue;
      final nom = entree.uri.pathSegments.where((p) => p.isNotEmpty).last;
      // Un chiffrement interrompu avant la réservation : rien à reprendre.
      if (nom.startsWith('prep-')) {
        await _effacerDossier(entree.path);
        continue;
      }
      if (_actifs.containsKey(nom)) continue;
      final registre = await _lireRegistre(nom);
      if (registre == null) {
        await _effacerDossier(entree.path);
        continue;
      }
      final r = ReservationEnvoi.depuisJson(registre['reservation'] as Map<String, dynamic>);
      final chemin =
          registre['fichier'] as String? ?? '$dossierEnvoisMorceaux/$nom/chiffre.bin';
      // Le fichier n'est plus là (la file d'envoi en clair l'a déjà oublié) :
      // rien à pousser. Si l'envoi vit encore, c'est elle qui le reprendra.
      if (!File('$racine/$chemin').existsSync()) {
        await _effacerDossier(entree.path);
        continue;
      }
      final s = EnvoiMorceauxSuivi(
        reservation: r,
        convId: registre['convId'] as String? ?? '',
        cheminRelatif: chemin,
        messageId: registre['messageId'] as String?,
        morceaux: morceauxDe(_tailleDe(chemin), r.tailleMorceau),
      );
      _actifs[r.id] = s;
      await _verifier(s, relire: true);
    }
  }

  // ═══════════════════════ REGISTRE ═══════════════════════
  //
  // Un fichier `envoi.json` à côté du chiffré : ce qu'il faut pour retrouver
  // l'envoi après que le système a tué l'application — le jeton d'envoi
  // compris, sans lequel on ne pourrait plus parler de cet envoi au serveur.

  Future<void> _ecrireRegistre(
    ReservationEnvoi r, {
    required String convId,
    String? messageId,
    required String fichier,
  }) async {
    final f = File('$_racine/$dossierEnvoisMorceaux/${r.id}/envoi.json');
    await f.writeAsString(jsonEncode({
      'reservation': r.toJson(),
      'convId': convId,
      if (messageId != null) 'messageId': messageId,
      'fichier': fichier,
      'creeA': DateTime.now().toIso8601String(),
    }));
  }

  Future<Map<String, dynamic>?> _lireRegistre(String id) async {
    try {
      final j = jsonDecode(
          await File('$_racine/$dossierEnvoisMorceaux/$id/envoi.json').readAsString());
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _effacerDossier(String chemin) async {
    try {
      final d = Directory(chemin);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
