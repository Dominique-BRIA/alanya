import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../core/centre_transferts.dart';
import '../../core/compression_envoi.dart';
import '../../core/compression_image.dart' show ResultatCompression;
import '../../core/connectivity_service.dart';
import '../../core/locale_controller.dart';
import '../../core/message_cache.dart';
import '../../core/plafond_media.dart';
import '../../core/realtime_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/e2ee/e2ee_fournisseur.dart';
import '../../services/e2ee/e2ee_media_envoi.dart';
import '../../widgets/media/media_picker_sheet.dart';
import '../media/media_repository.dart';
import 'chat_repository.dart';
import 'envoi_media.dart';
import 'envoi_media_store.dart';
import 'envoi_morceaux/envoi_morceaux_chiffre.dart';

/// LES ENVOIS DE MÉDIAS QUI VIVENT HORS DE L'ÉCRAN DE DISCUSSION (21/11/2026).
///
/// 🔴 « LA COMPRESSION DOIT CONTINUER MÊME SI ON QUITTE LA CONVERSATION, MÊME
/// SI L'APPLICATION EST FERMÉE, MÊME SI ON SORT DE L'APPLICATION » (user).
/// Puis : « si on veut annuler l'envoi d'un fichier, ou s'il échoue, un moyen
/// de le relancer existe ? » (user, même jour).
///
/// Ce service porte un envoi de médias à travers quatre états, sans écran :
///
///   · [EtatPreparation.compression] : Envoyer a été pressé pendant la
///     compression de ses vidéos ; on attend qu'elle finisse ;
///   · [EtatPreparation.envoi] : le fichier se chiffre et part, par les
///     chemins habituels — magasin des envois en clair, envoi chiffré en
///     morceaux (Android continue application fermée), repli d'un seul bloc ;
///   · [EtatPreparation.attenteReseau] : pas de réseau ; il repart seul au
///     retour du réseau ;
///   · [EtatPreparation.echec] : un refus ; la bulle propose « Réessayer » et
///     « Supprimer ».
///
/// Il reçoit aussi les envois CHIFFRÉS ratés de l'écran de discussion : ils
/// n'avaient ni file hors ligne ni « Réessayer », la bulle disparaissait.
///
/// ⚠️ TENIR SANS ÉCRAN :
///   · une entrée du [CentreTransferts] pendant la compression tient le
///     service Android de premier plan, donc le processus ;
///   · l'envoi est RANGÉ SUR LE DISQUE (stockage privé de l'application) et
///     repris au lancement suivant si Android ferme quand même l'application.
///
/// ⚠️ MÉMOIRE : une vidéo n'est jamais lue ici. Seuls les fichiers qui
/// n'existaient déjà qu'en mémoire (photos réduites, quelques Mo) sont écrits
/// sur le disque pour être rangés, et relus à la reprise.
///
/// ⚠️ CHIFFREMENT : rien n'est chiffré ici. Un fil chiffré passe par les mêmes
/// fonctions que l'écran (`SuiviEnvoisMorceaux.lancer`,
/// `EnvoiMediaChiffre.envoyer`) ; un nouvel essai rechiffre avec une clé
/// neuve. Rien ne part jamais en clair vers le serveur dans un fil chiffré.
class PreparationsEnvoi extends ChangeNotifier {
  PreparationsEnvoi._();
  static final instance = PreparationsEnvoi._();

  static const _dossier = 'preparations_envoi';

  final Map<String, PreparationEnCours> _enCours = {};

  /// Les services, pour reprendre sans écran (voir [brancher]).
  MediaRepository? _medias;
  ChatRepository? _chat;
  RealtimeClient? _rt;
  ConnectivityService? _conn;
  PileE2ee? Function()? _pile;
  bool _relu = false;

  /// Les envois d'une conversation : l'écran en fait des bulles.
  List<PreparationEnCours> pour(String convId) =>
      _enCours.values.where((p) => p.convId == convId).toList();

  PreparationEnCours? parId(String id) => _enCours[id];

  /// Branche les services et REPREND ce qui attendait quand l'application a
  /// été fermée. Appelé par l'accueil, une fois connecté (la pile de
  /// chiffrement n'existe qu'à ce moment).
  Future<void> brancher({
    required MediaRepository medias,
    required ChatRepository chat,
    required RealtimeClient rt,
    required ConnectivityService conn,
    required PileE2ee? Function() pile,
  }) async {
    _medias = medias;
    _chat = chat;
    _rt = rt;
    _pile = pile;
    if (!identical(conn, _conn)) {
      _conn?.removeListener(_auRetourDuReseau);
      _conn = conn;
      conn.addListener(_auRetourDuReseau);
    }
    // Ce qui attendait (réseau, chiffrement pas encore prêt) repart.
    _auRetourDuReseau();
    if (_relu) return;
    _relu = true;
    await _reprendreDuDisque();
  }

  // ═══════════════════════ LES ENTRÉES ═══════════════════════

  /// Un envoi pressé PENDANT la compression de ses vidéos.
  ///
  /// [fichiers] : la liste telle qu'à l'appui sur Envoyer (des originaux) ;
  /// [compresses] : la même, compressée, quand la compression a fini ;
  /// [annulerCompression] : arrête la compression (« Annuler » de la bulle).
  /// [chiffre] : le fil est chiffré — [pairId] nul pour un groupe.
  Future<void> lancer({
    required String convId,
    required List<MediaPickResult> fichiers,
    required Future<List<MediaPickResult>> compresses,
    required ValueListenable<double> avancement,
    VoidCallback? annulerCompression,
    required String? legende,
    required List<Map<String, String>> mentions,
    required String? replyToId,
    required bool vueUnique,
    required bool chiffre,
    required String? pairId,
    required String? moi,
  }) async {
    final p = PreparationEnCours._(
      id: "tmp-preparation-${DateTime.now().microsecondsSinceEpoch}",
      convId: convId,
      fichiers: fichiers,
      legende: legende,
      mentions: mentions,
      replyToId: replyToId,
      vueUnique: vueUnique,
      chiffre: chiffre,
      pairId: pairId,
      moi: moi,
      creeA: DateTime.now(),
      etat: EtatPreparation.compression,
    );
    p._annulerCompression = annulerCompression;
    _enCours[p.id] = p;
    notifyListeners();
    _annoncer(p);
    // Rangé AVANT d'attendre : si Android ferme l'application pendant la
    // compression, l'envoi repart au prochain lancement.
    await _ranger(p);

    void suivre() => _avancer(p, avancement.value);
    avancement.addListener(suivre);
    List<MediaPickResult> prets;
    try {
      prets = await compresses;
    } catch (_) {
      // Une compression qui échoue laisse l'original : il part tel quel.
      prets = fichiers;
    } finally {
      avancement.removeListener(suivre);
    }
    _retirerAnnonce(p);
    if (p.annule) return;
    p.fichiers = prets;
    p.compresses = true;
    await _ranger(p);
    await _envoyer(p);
  }

  /// Un envoi CHIFFRÉ que l'écran de discussion n'a pas pu faire partir : il
  /// attend le réseau ([reseau]) ou montre son échec, avec « Réessayer ».
  ///
  /// [fichier] est déjà prêt (compressé) : il repart tel quel, chiffré de
  /// nouveau avec une clé neuve.
  Future<void> confierApresEchec({
    required String convId,
    required MediaPickResult fichier,
    required String legende,
    required String? replyToId,
    required bool vueUnique,
    required String? pairId,
    required String moi,
    required bool reseau,
    String? erreur,
  }) async {
    final p = PreparationEnCours._(
      id: "tmp-preparation-${DateTime.now().microsecondsSinceEpoch}",
      convId: convId,
      fichiers: [fichier],
      legende: legende.isEmpty ? null : legende,
      mentions: const [],
      replyToId: replyToId,
      vueUnique: vueUnique,
      chiffre: true,
      pairId: pairId,
      moi: moi,
      creeA: DateTime.now(),
      etat: reseau ? EtatPreparation.attenteReseau : EtatPreparation.echec,
    );
    p.compresses = true;
    p.erreur = erreur;
    _enCours[p.id] = p;
    notifyListeners();
    await _ranger(p);
    // Le réseau est peut-être déjà revenu entre-temps.
    if (reseau) _auRetourDuReseau();
  }

  // ═══════════════════════ LES GESTES ═══════════════════════

  /// « Annuler » ou « Supprimer » : la compression s'arrête, rien ne part, et
  /// l'envoi est oublié — y compris de la reprise au prochain lancement.
  Future<void> annuler(String id) async {
    final p = _enCours[id];
    if (p == null) return;
    p.annule = true;
    p._annulerCompression?.call();
    await _oublier(p);
  }

  /// « Réessayer » sur un envoi échoué.
  void reessayer(String id) {
    final p = _enCours[id];
    if (p == null || p.etat != EtatPreparation.echec) return;
    unawaited(p.compresses ? _envoyer(p) : _recompresserPuisEnvoyer(p));
  }

  // ═══════════════════════ L'ENVOI ═══════════════════════

  Future<void> _envoyer(PreparationEnCours p) async {
    if (p.annule || p._envoiEnCours) return;
    p._envoiEnCours = true;
    p.etat = EtatPreparation.envoi;
    p.erreur = null;
    p.avancement.value = 0;
    notifyListeners();
    try {
      // Le plafond se mesure APRÈS la compression, comme à l'écran d'aperçu.
      final tropGros = [
        for (final f in p.fichiers)
          if (depassePlafondMedia(f.taille)) f.fileName
      ];
      p.fichiers = [
        for (final f in p.fichiers)
          if (!depassePlafondMedia(f.taille)) f
      ];
      if (tropGros.isNotEmpty) showAppSnackBar(_avisEcartes(tropGros));

      if (p.fichiers.isNotEmpty) {
        if (p.chiffre) {
          await _envoyerChiffre(p);
        } else {
          _envoyerEnClair(p);
        }
      }
      await _oublier(p);
    } catch (e) {
      p._envoiEnCours = false;
      if (p.annule || e is EnvoiAnnule) {
        await _oublier(p);
        return;
      }
      final attendre = e is _PasEncorePret || _estPanneReseau(e);
      p.etat = attendre ? EtatPreparation.attenteReseau : EtatPreparation.echec;
      p.erreur = e is ApiException ? e.message : null;
      notifyListeners();
      await _ranger(p);
      // Le chiffrement démarre juste après la connexion : un envoi repris au
      // lancement peut arriver avant lui. Le réseau, lui, est peut-être là et
      // ne changera pas — on réessaie donc seul, dans quelques secondes.
      if (e is _PasEncorePret) {
        Timer(const Duration(seconds: 10), _auRetourDuReseau);
      }
    }
  }

  /// Fil EN CLAIR : le magasin des envois, comme l'écran — par paquets de 10,
  /// la limite du serveur. Il a ses propres bulles, son « Annuler », son
  /// « Réessayer » et sa file hors ligne : on lui confie l'envoi SANS
  /// l'attendre, sans quoi deux bulles montreraient le même fichier.
  void _envoyerEnClair(PreparationEnCours p) {
    final medias = _medias, chat = _chat, rt = _rt, conn = _conn;
    if (medias == null || chat == null || rt == null || conn == null) {
      throw const _PasEncorePret();
    }
    final fichiers = p.fichiers;
    final lots = <EnvoiMedia>[];
    for (var debut = 0; debut < fichiers.length; debut += 10) {
      final lot = fichiers.sublist(
          debut, debut + 10 > fichiers.length ? fichiers.length : debut + 10);
      lots.add(EnvoiMedia(
        tempId: "tmp-${DateTime.now().microsecondsSinceEpoch}-$debut",
        convId: p.convId,
        fichiers: lot,
        msgType: _typePour(lot.first.mimeType),
        legende: debut == 0 ? p.legende : null,
        mentions: debut == 0 ? p.mentions : null,
        replyToId: debut == 0 ? p.replyToId : null,
        // Une vue unique n'a qu'un fichier : le paquet est forcément le seul.
        vueUnique: p.vueUnique && lot.length == 1,
      ));
    }
    // Un paquet après l'autre : dix téléversements en parallèle sur une
    // connexion mobile les ralentiraient tous.
    unawaited(() async {
      for (final envoi in lots) {
        await EnvoiMediaStore.instance.lancer(
          envoi,
          media: medias,
          chat: chat,
          rt: rt,
          messageErreurGenerique: () => _texte('send_failed'),
          conn: conn,
        );
      }
    }());
  }

  /// Fil CHIFFRÉ : un message par fichier, comme l'écran. En morceaux d'abord
  /// (Android continue application fermée), d'un seul bloc en repli. Un
  /// fichier parti est retiré de la liste : un nouvel essai ne renvoie que ce
  /// qui reste, et la légende ne part qu'une fois.
  Future<void> _envoyerChiffre(PreparationEnCours p) async {
    final pile = _pile?.call();
    final medias = _medias;
    final moi = p.moi;
    if (pile == null || medias == null || moi == null) {
      throw const _PasEncorePret();
    }
    final vueUnique = p.vueUnique && p.fichiers.length == 1;
    while (p.fichiers.isNotEmpty) {
      final f = p.fichiers.first;
      final legende = p.legendeEnvoyee ? '' : (p.legende ?? '');
      final replyToId = p.legendeEnvoyee ? null : p.replyToId;
      EnvoiMorceauxSuivi? suivi;
      if (SuiviEnvoisMorceaux.instance.pret) {
        try {
          suivi = await SuiviEnvoisMorceaux.instance.lancer(
            fil: pile.fil,
            convId: p.convId,
            pairId: p.pairId,
            fichier: f,
            legende: legende,
            replyToId: replyToId,
            vueUnique: vueUnique,
            annule: () => p.annule,
            onPreparation: (v) => p.avancement.value = v,
            rangerMaCopie: (id, d) => EnvoiMediaChiffre.rangerMaCopie(
              pile: pile,
              convId: p.convId,
              moi: moi,
              id: id,
              d: d,
              legende: legende,
              replyToId: replyToId,
              vueUnique: vueUnique,
              octets: f.surDisque ? null : f.bytes,
              cheminClair: f.fichierContenu,
            ),
          );
        } on ApiException catch (e) {
          // Un serveur sans envoi en morceaux : un seul bloc.
          if (e.statusCode != 404) rethrow;
        }
      }
      if (suivi != null) {
        unawaited(_suivreJusquAuBout(
          suivi,
          pile: pile,
          convId: p.convId,
          pairId: p.pairId,
          moi: moi,
          fichier: f,
          legende: legende,
          replyToId: replyToId,
          vueUnique: vueUnique,
        ));
      } else {
        await EnvoiMediaChiffre.envoyer(
          pile: pile,
          medias: medias,
          convId: p.convId,
          pairId: p.pairId,
          moi: moi,
          fichier: f,
          legende: legende,
          replyToId: replyToId,
          vueUnique: vueUnique,
          annule: () => p.annule,
        );
      }
      p.fichiers = p.fichiers.sublist(1);
      p.legendeEnvoyee = true;
    }
  }

  /// Un envoi en morceaux lancé d'ici : Android l'envoie, le serveur le
  /// publie. Comme l'écran ([_suivreEnvoiMorceaux] de la discussion) :
  ///   · publication refusée (clé de groupe changée en route) → le message
  ///     repart par le chemin ordinaire, avec le MÊME média déjà arrivé ;
  ///   · échec → « Réessayer », sauf si l'utilisateur l'a annulé.
  Future<void> _suivreJusquAuBout(
    EnvoiMorceauxSuivi suivi, {
    required PileE2ee pile,
    required String convId,
    required String? pairId,
    required String moi,
    required MediaPickResult fichier,
    required String legende,
    required String? replyToId,
    required bool vueUnique,
  }) async {
    try {
      final etat = await suivi.fin;
      if (etat.publie) return;
      final d = suivi.message!.mediaChiffre!;
      final id = await pile.fil.envoyerMedia(
        convId: convId,
        pairId: pairId,
        media: d,
        legende: legende,
        replyToId: replyToId,
        vueUnique: vueUnique,
      );
      await EnvoiMediaChiffre.rangerMaCopie(
        pile: pile,
        convId: convId,
        moi: moi,
        id: id,
        d: d,
        legende: legende,
        replyToId: replyToId,
        vueUnique: vueUnique,
      );
    } catch (e) {
      if (e is EnvoiAnnule) return;
      await abandonnerEnvoiMorceaux(suivi);
      await confierApresEchec(
        convId: convId,
        fichier: fichier,
        legende: legende,
        replyToId: replyToId,
        vueUnique: vueUnique,
        pairId: pairId,
        moi: moi,
        reseau: _estPanneReseau(e),
        erreur: e is ApiException ? e.message : null,
      );
    }
  }

  // ═══════════════════════ LA REPRISE ═══════════════════════

  void _auRetourDuReseau() {
    if (_conn?.isOnline != true) return;
    for (final p in _enCours.values.toList()) {
      if (p.etat != EtatPreparation.attenteReseau || p._envoiEnCours) continue;
      unawaited(p.compresses ? _envoyer(p) : _recompresserPuisEnvoyer(p));
    }
  }

  /// Ce qui attendait quand l'application a été fermée : recompressé depuis
  /// les originaux si besoin, puis envoyé. Un échec reste un échec, avec son
  /// « Réessayer ».
  Future<void> _reprendreDuDisque() async {
    final racine = await _racine();
    if (racine == null || !await racine.exists()) return;
    await for (final d in racine.list()) {
      if (d is! Directory) continue;
      try {
        final p = await _relire(d);
        if (p == null) {
          await d.delete(recursive: true);
          continue;
        }
        if (_enCours.containsKey(p.id)) continue;
        _enCours[p.id] = p;
        notifyListeners();
        if (p.etat == EtatPreparation.echec) continue;
        if (p.etat == EtatPreparation.attenteReseau && _conn?.isOnline != true) continue;
        unawaited(p.compresses ? _envoyer(p) : _recompresserPuisEnvoyer(p));
      } catch (e) {
        debugPrint('[preparations] envoi illisible, abandonné : $e');
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _recompresserPuisEnvoyer(PreparationEnCours p) async {
    if (p.annule || p._envoiEnCours) return;
    p.etat = EtatPreparation.compression;
    notifyListeners();
    _annoncer(p);
    final aFaire = [for (final f in p.fichiers) if (!f.compresse && f.estVideo) f];
    final prets = <MediaPickResult>[];
    var n = 0;
    for (final f in p.fichiers) {
      if (p.annule) break;
      if (!aFaire.contains(f)) {
        prets.add(f);
        continue;
      }
      final rang = n++;
      try {
        final r = await compresserPourEnvoi(
          octets: f.bytes,
          nomFichier: f.fileName,
          mimeType: f.mimeType,
          chemin: f.path,
          onProgression: (v) => _avancer(p, (rang + v) / aFaire.length),
        );
        prets.add(appliquerCompression(f, r));
      } catch (_) {
        prets.add(f);
      }
    }
    _retirerAnnonce(p);
    if (p.annule) return;
    p.fichiers = prets;
    p.compresses = true;
    await _ranger(p);
    await _envoyer(p);
  }

  // ═══════════════════════ LE DISQUE ═══════════════════════

  Future<Directory?> _racine() async {
    if (kIsWeb) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.path}/$_dossier');
    } catch (_) {
      return null;
    }
  }

  /// Range l'envoi : sa description, et les octets des fichiers qui n'existent
  /// qu'en mémoire (photos déjà réduites). Une vidéo n'est jamais recopiée :
  /// on garde son chemin.
  Future<void> _ranger(PreparationEnCours p) async {
    if (p.annule) return;
    final racine = await _racine();
    if (racine == null) return;
    try {
      final dossier = Directory('${racine.path}/${p.id}');
      await dossier.create(recursive: true);
      final fichiers = <Map<String, dynamic>>[];
      for (var i = 0; i < p.fichiers.length; i++) {
        final f = p.fichiers[i];
        String? octets;
        if (!f.surDisque && f.bytes.isNotEmpty) {
          octets = 'octets-${identityHashCode(f)}';
          final o = File('${dossier.path}/$octets');
          if (!await o.exists()) await o.writeAsBytes(f.bytes, flush: true);
        }
        fichiers.add({
          'nom': f.fileName,
          'mime': f.mimeType,
          if (f.path != null) 'chemin': f.path,
          if (f.cheminContenu != null) 'cheminContenu': f.cheminContenu,
          if (f.durationMs != null) 'dureeMs': f.durationMs,
          if (f.tailleSurDisque != null) 'tailleSurDisque': f.tailleSurDisque,
          if (octets != null) 'octets': octets,
          'compresse': f.compresse,
          'sensible': f.sensible,
        });
      }
      final meta = {
        'id': p.id,
        'convId': p.convId,
        'legende': p.legende,
        'legendeEnvoyee': p.legendeEnvoyee,
        'mentions': p.mentions,
        'replyToId': p.replyToId,
        'vueUnique': p.vueUnique,
        'chiffre': p.chiffre,
        'pairId': p.pairId,
        'moi': p.moi,
        'creeA': p.creeA.millisecondsSinceEpoch,
        'compresses': p.compresses,
        'etat': p.etat.name,
        if (p.erreur != null) 'erreur': p.erreur,
        'fichiers': fichiers,
      };
      final f = File('${dossier.path}/envoi.json');
      final provisoire = File('${dossier.path}/envoi.json.tmp');
      await provisoire.writeAsString(jsonEncode(meta), flush: true);
      await provisoire.rename(f.path);
    } catch (e) {
      debugPrint('[preparations] rangement impossible : $e');
    }
  }

  Future<PreparationEnCours?> _relire(Directory dossier) async {
    final f = File('${dossier.path}/envoi.json');
    if (!await f.exists()) return null;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    var compresses = m['compresses'] == true;
    final fichiers = <MediaPickResult>[];
    for (final brut in (m['fichiers'] as List)) {
      final x = brut as Map<String, dynamic>;
      final octetsNom = x['octets'] as String?;
      final chemin = x['chemin'] as String?;
      var cheminContenu = x['cheminContenu'] as String?;
      var compresse = x['compresse'] == true;
      Uint8List octets = Uint8List(0);
      int? tailleSurDisque = (x['tailleSurDisque'] as num?)?.toInt();
      if (octetsNom != null) {
        final o = File('${dossier.path}/$octetsNom');
        if (!await o.exists()) continue;
        octets = await o.readAsBytes();
      } else {
        // La vidéo compressée a disparu (cache vidé) mais l'original est là :
        // on la recompressera.
        if (cheminContenu != null && !await File(cheminContenu).exists()) {
          cheminContenu = null;
          compresse = false;
          compresses = false;
          tailleSurDisque = null;
        }
        final source = cheminContenu ?? chemin;
        if (source == null || !await File(source).exists()) continue;
        tailleSurDisque ??= await File(source).length();
      }
      fichiers.add(MediaPickResult(
        bytes: octets,
        fileName: x['nom'] as String,
        mimeType: x['mime'] as String,
        durationMs: (x['dureeMs'] as num?)?.toInt(),
        path: chemin,
        cheminContenu: cheminContenu,
        tailleSurDisque: octetsNom != null ? null : tailleSurDisque,
        compresse: compresse,
        sensible: x['sensible'] == true,
      ));
    }
    if (fichiers.isEmpty) return null;
    final etat = EtatPreparation.values.firstWhere(
      (e) => e.name == m['etat'],
      orElse: () => EtatPreparation.attenteReseau,
    );
    final p = PreparationEnCours._(
      id: m['id'] as String,
      convId: m['convId'] as String,
      fichiers: fichiers,
      legende: m['legende'] as String?,
      mentions: [
        for (final x in (m['mentions'] as List? ?? const []))
          Map<String, String>.from(x as Map)
      ],
      replyToId: m['replyToId'] as String?,
      vueUnique: m['vueUnique'] == true,
      chiffre: m['chiffre'] == true,
      pairId: m['pairId'] as String?,
      moi: m['moi'] as String?,
      creeA: DateTime.fromMillisecondsSinceEpoch((m['creeA'] as num).toInt()),
      // Une compression ou un envoi coupés par la fermeture repartent ; un
      // échec reste un échec.
      etat: etat == EtatPreparation.echec ? etat : EtatPreparation.attenteReseau,
    );
    p.compresses = compresses;
    p.legendeEnvoyee = m['legendeEnvoyee'] == true;
    p.erreur = m['erreur'] as String?;
    return p;
  }

  Future<void> _oublier(PreparationEnCours p) async {
    _enCours.remove(p.id);
    _retirerAnnonce(p);
    // L'anneau n'est pas libéré : une bulle peut l'écouter jusqu'à son
    // prochain dessin. Il part avec l'envoi.
    notifyListeners();
    final racine = await _racine();
    if (racine == null) return;
    try {
      final d = Directory('${racine.path}/${p.id}');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  // ═══════════════════════ OUTILS ═══════════════════════

  /// L'entrée du centre des transferts pendant la compression : c'est ELLE
  /// qui tient le service Android de premier plan, donc l'application en vie
  /// hors de l'écran. Retirée dès la fin : attendre le réseau ne doit pas
  /// garder ce service (et la batterie) en marche.
  void _annoncer(PreparationEnCours p) {
    if (p._annonce) return;
    p._annonce = true;
    CentreTransferts.instance.demarrer(
      id: p.id,
      sorte: SorteTransfert.envoi,
      titre: _texte('envoi_compression'),
    );
  }

  void _retirerAnnonce(PreparationEnCours p) {
    if (!p._annonce) return;
    p._annonce = false;
    CentreTransferts.instance.reussir(p.id);
  }

  void _avancer(PreparationEnCours p, double v) {
    final x = v.clamp(0.0, 1.0);
    p.avancement.value = x;
    if (p._annonce) CentreTransferts.instance.avancer(p.id, x);
  }

  bool _estPanneReseau(Object e) => estPanneReseau(e);

  /// Une coupure (et non un refus du serveur) : l'envoi attend le réseau.
  static bool estPanneReseau(Object e) {
    if (e is ApiException) return false;
    return e is SocketException || e is ClientException || e is TimeoutException;
  }

  /// Un texte dans la langue choisie, sans écran.
  static String _texte(String cle, [Map<String, String>? params]) {
    var s = AppLocalizations(LocaleController.codeCourant).get(cle);
    params?.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  static String _avisEcartes(List<String> noms) => noms.length == 1
      ? _texte('media_skipped_one', {'nom': noms.first, 'plafond': '$plafondMediaMo'})
      : _texte('media_skipped_many', {'n': '${noms.length}', 'plafond': '$plafondMediaMo'});

  static String _typePour(String mime) {
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    return 'FILE';
  }
}

/// La pile de chiffrement ou les services ne sont pas encore prêts (juste
/// après le lancement) : l'envoi attend et réessaie seul.
class _PasEncorePret implements Exception {
  const _PasEncorePret();
}

/// Où en est un envoi de [PreparationsEnvoi].
enum EtatPreparation { compression, envoi, attenteReseau, echec }

/// Un envoi de médias porté par [PreparationsEnvoi].
class PreparationEnCours {
  PreparationEnCours._({
    required this.id,
    required this.convId,
    required this.fichiers,
    required this.legende,
    required this.mentions,
    required this.replyToId,
    required this.vueUnique,
    required this.chiffre,
    required this.pairId,
    required this.moi,
    required this.creeA,
    required this.etat,
  }) : premier = fichiers.first;

  /// Identifiant de la bulle.
  final String id;
  final String convId;

  /// Ce qui reste à envoyer : originaux avant la compression, versions
  /// compressées ensuite, et seulement ce qui n'est pas encore parti.
  List<MediaPickResult> fichiers;
  final String? legende;
  final List<Map<String, String>> mentions;
  final String? replyToId;
  final bool vueUnique;
  final bool chiffre;
  final String? pairId;
  final String? moi;
  final DateTime creeA;

  EtatPreparation etat;

  /// Le message du serveur, quand il a refusé.
  String? erreur;

  /// L'avancement en cours (compression, puis chiffrement) : l'anneau.
  final ValueNotifier<double> avancement = ValueNotifier<double>(0);

  /// Le premier fichier : la vignette et le type de la bulle.
  final MediaPickResult premier;

  String get msgType {
    final mime = premier.mimeType;
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    return 'FILE';
  }

  /// Les vidéos sont-elles déjà compressées ?
  bool compresses = false;

  /// La légende est partie avec un premier fichier.
  bool legendeEnvoyee = false;

  /// « Annuler » ou « Supprimer » a été pressé.
  bool annule = false;

  VoidCallback? _annulerCompression;
  bool _envoiEnCours = false;
  bool _annonce = false;
}

/// Abandonne un envoi en morceaux raté : fichier partiel et publication prévue
/// effacés chez le serveur, copie locale du message retirée — il ne partira
/// jamais sous cet identifiant.
Future<void> abandonnerEnvoiMorceaux(EnvoiMorceauxSuivi suivi) async {
  try {
    await SuiviEnvoisMorceaux.instance.abandonner(suivi.reservation);
  } catch (_) {}
  final id = suivi.messageId;
  if (id != null) {
    try {
      await MessageCache.remove(id);
    } catch (_) {}
  }
}

/// Remplace [m] par le résultat de sa compression — la règle de l'écran
/// d'aperçu, pour la reprise après fermeture.
MediaPickResult appliquerCompression(MediaPickResult m, ResultatCompression pret) =>
    m.surDisque
        ? m.copieAvec(
            cheminContenu: pret.cheminProduit,
            tailleSurDisque: pret.cheminProduit != null ? pret.tailleApres : null,
            fileName: pret.nomFichier,
            mimeType: pret.mimeType,
            compresse: pret.compresse,
            tailleOriginale: pret.compresse ? pret.tailleAvant : null,
            niveauSuperieurPossible: pret.niveauSuperieurPossible,
            definitionAutreNiveau: pret.definitionAutreNiveau,
          )
        : m.copieAvec(
            bytes: pret.octets,
            fileName: pret.nomFichier,
            mimeType: pret.mimeType,
            compresse: pret.compresse,
            tailleOriginale: pret.compresse ? pret.tailleAvant : null,
            niveauSuperieurPossible: pret.niveauSuperieurPossible,
            definitionAutreNiveau: pret.definitionAutreNiveau,
          );
