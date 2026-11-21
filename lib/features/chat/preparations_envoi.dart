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

/// LES ENVOIS QUI ATTENDENT LA FIN D'UNE COMPRESSION (21/11/2026).
///
/// 🔴 « LA COMPRESSION DOIT CONTINUER MÊME SI ON QUITTE LA CONVERSATION, MÊME
/// SI L'APPLICATION EST FERMÉE, MÊME SI ON SORT DE L'APPLICATION » (user).
///
/// On appuie sur Envoyer pendant que la vidéo se compresse : l'écran d'aperçu
/// se ferme, et c'est CE SERVICE, et non l'écran de discussion, qui attend la
/// fin de la compression puis lance l'envoi ordinaire — le magasin des envois
/// en clair, ou l'envoi chiffré en morceaux. Aucun écran n'est nécessaire :
///
///   · on quitte la discussion → rien ne change, elle remontre la bulle
///     « Compression… » quand on y revient ;
///   · on sort de l'application → une entrée du [CentreTransferts] tient le
///     service Android de premier plan, donc le processus, donc la
///     compression ;
///   · Android ferme quand même l'application → l'envoi est RANGÉ SUR LE
///     DISQUE dès le départ, et repris au lancement suivant ([reprendre]) :
///     la vidéo est recompressée depuis l'original, puis envoyée.
///
/// ⚠️ RIEN NE PART AVANT LA FIN DE LA COMPRESSION : l'original enverrait les
/// mégaoctets qu'on est justement en train de retirer.
///
/// ⚠️ LE CHIFFREMENT NE CHANGE PAS : un fil chiffré passe par les mêmes
/// fonctions que l'écran de discussion (`SuiviEnvoisMorceaux.lancer`, repli
/// `EnvoiMediaChiffre.envoyer`), qui ne dépendaient déjà d'aucun écran.
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

  /// Les envois en préparation d'une conversation : l'écran en fait des
  /// bulles « Compression… ».
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

  /// Lance un envoi pressé PENDANT la compression de ses vidéos.
  ///
  /// [fichiers] : la liste telle qu'à l'appui sur Envoyer (des originaux) ;
  /// [compresses] : la même, compressée, quand la compression a fini.
  /// [chiffre] : le fil est chiffré — [pairId] nul pour un groupe.
  Future<void> lancer({
    required String convId,
    required List<MediaPickResult> fichiers,
    required Future<List<MediaPickResult>> compresses,
    required ValueListenable<double> avancement,
    required String? legende,
    required List<Map<String, String>> mentions,
    required String? replyToId,
    required bool vueUnique,
    required bool chiffre,
    required String? pairId,
    required String? moi,
  }) async {
    final p = PreparationEnCours._(
      id: "tmp-compression-${DateTime.now().microsecondsSinceEpoch}",
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
    );
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
    p._prets = prets;
    await _envoyer(p, prets);
  }

  // ═══════════════════════ L'ENVOI ═══════════════════════

  Future<void> _envoyer(PreparationEnCours p, List<MediaPickResult> prets) async {
    if (p._envoiEnCours) return;
    p._envoiEnCours = true;
    _avancer(p, 1);
    try {
      // Le plafond se mesure APRÈS la compression, comme à l'écran d'aperçu.
      final tropGros = [
        for (final f in prets)
          if (depassePlafondMedia(f.taille)) f.fileName
      ];
      final aEnvoyer = [
        for (final f in prets)
          if (!depassePlafondMedia(f.taille)) f
      ];
      if (tropGros.isNotEmpty) showAppSnackBar(_avisEcartes(tropGros));

      if (aEnvoyer.isNotEmpty) {
        if (p.chiffre) {
          await _envoyerChiffre(p, aEnvoyer);
        } else {
          await _envoyerEnClair(p, aEnvoyer);
        }
      }
      await _oublier(p);
    } catch (e) {
      p._envoiEnCours = false;
      if (_estPanneReseau(e)) {
        // Pas de réseau : l'envoi reste rangé et repart au retour du réseau.
        p._attendReseau = true;
        return;
      }
      showAppSnackBar(_texte('send_failed'));
      await _oublier(p);
    }
  }

  /// Fil EN CLAIR : le magasin des envois, comme l'écran — par paquets de 10,
  /// la limite du serveur. Il garde lui-même ses envois sur le disque.
  Future<void> _envoyerEnClair(PreparationEnCours p, List<MediaPickResult> fichiers) async {
    final medias = _medias, chat = _chat, rt = _rt, conn = _conn;
    if (medias == null || chat == null || rt == null || conn == null) {
      throw StateError('Services non branchés');
    }
    for (var debut = 0; debut < fichiers.length; debut += 10) {
      final lot = fichiers.sublist(
          debut, debut + 10 > fichiers.length ? fichiers.length : debut + 10);
      final envoi = EnvoiMedia(
        tempId: "tmp-${DateTime.now().microsecondsSinceEpoch}-$debut",
        convId: p.convId,
        fichiers: lot,
        msgType: _typePour(lot.first.mimeType),
        legende: debut == 0 ? p.legende : null,
        mentions: debut == 0 ? p.mentions : null,
        replyToId: debut == 0 ? p.replyToId : null,
        vueUnique: p.vueUnique && lot.length == 1,
      );
      await EnvoiMediaStore.instance.lancer(
        envoi,
        media: medias,
        chat: chat,
        rt: rt,
        messageErreurGenerique: () => _texte('send_failed'),
        conn: conn,
      );
    }
  }

  /// Fil CHIFFRÉ : un message par fichier, comme l'écran. En morceaux d'abord
  /// (Android continue application fermée), d'un seul bloc en repli.
  Future<void> _envoyerChiffre(PreparationEnCours p, List<MediaPickResult> fichiers) async {
    final pile = _pile?.call();
    final medias = _medias;
    final moi = p.moi;
    if (pile == null || medias == null || moi == null) {
      throw const SocketException('Chiffrement pas encore prêt');
    }
    final vueUnique = p.vueUnique && fichiers.length == 1;
    for (var i = 0; i < fichiers.length; i++) {
      final f = fichiers[i];
      final legende = i == 0 ? (p.legende ?? '') : '';
      final replyToId = i == 0 ? p.replyToId : null;
      if (SuiviEnvoisMorceaux.instance.pret) {
        try {
          await SuiviEnvoisMorceaux.instance.lancer(
            fil: pile.fil,
            convId: p.convId,
            pairId: p.pairId,
            fichier: f,
            legende: legende,
            replyToId: replyToId,
            vueUnique: vueUnique,
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
          continue;
        } on ApiException catch (e) {
          // Un serveur sans envoi en morceaux : un seul bloc.
          if (e.statusCode != 404) rethrow;
        }
      }
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
      );
    }
  }

  // ═══════════════════════ LA REPRISE ═══════════════════════

  void _auRetourDuReseau() {
    if (_conn?.isOnline != true) return;
    for (final p in _enCours.values.toList()) {
      if (p._attendReseau && p._prets != null) {
        p._attendReseau = false;
        unawaited(_envoyer(p, p._prets!));
      }
    }
  }

  /// Ce qui attendait quand l'application a été fermée : recompressé depuis
  /// les originaux, puis envoyé.
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
        _annoncer(p);
        unawaited(_recompresserPuisEnvoyer(p));
      } catch (e) {
        debugPrint('[preparations] envoi illisible, abandonné : $e');
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _recompresserPuisEnvoyer(PreparationEnCours p) async {
    final aFaire = [for (final f in p.fichiers) if (!f.compresse && f.estVideo) f];
    final prets = <MediaPickResult>[];
    var n = 0;
    for (final f in p.fichiers) {
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
    p._prets = prets;
    await _envoyer(p, prets);
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
  /// qu'en mémoire (les photos déjà réduites). Une vidéo n'est jamais
  /// recopiée : son original reste où il est.
  Future<void> _ranger(PreparationEnCours p) async {
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
          octets = 'octets-$i';
          await File('${dossier.path}/$octets').writeAsBytes(f.bytes, flush: true);
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
        'mentions': p.mentions,
        'replyToId': p.replyToId,
        'vueUnique': p.vueUnique,
        'chiffre': p.chiffre,
        'pairId': p.pairId,
        'moi': p.moi,
        'creeA': p.creeA.millisecondsSinceEpoch,
        'fichiers': fichiers,
      };
      await File('${dossier.path}/envoi.json').writeAsString(jsonEncode(meta), flush: true);
    } catch (e) {
      debugPrint('[preparations] rangement impossible : $e');
    }
  }

  Future<PreparationEnCours?> _relire(Directory dossier) async {
    final f = File('${dossier.path}/envoi.json');
    if (!await f.exists()) return null;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final fichiers = <MediaPickResult>[];
    for (final brut in (m['fichiers'] as List)) {
      final x = brut as Map<String, dynamic>;
      final octetsNom = x['octets'] as String?;
      final chemin = x['chemin'] as String?;
      Uint8List octets = Uint8List(0);
      int? tailleSurDisque = (x['tailleSurDisque'] as num?)?.toInt();
      if (octetsNom != null) {
        final o = File('${dossier.path}/$octetsNom');
        if (!await o.exists()) continue;
        octets = await o.readAsBytes();
      } else {
        // Un fichier sur disque disparu entre-temps (cache vidé) : écarté.
        final source = (x['cheminContenu'] as String?) ?? chemin;
        if (source == null || !await File(source).exists()) continue;
        tailleSurDisque ??= await File(source).length();
      }
      fichiers.add(MediaPickResult(
        bytes: octets,
        fileName: x['nom'] as String,
        mimeType: x['mime'] as String,
        durationMs: (x['dureeMs'] as num?)?.toInt(),
        path: chemin,
        cheminContenu: x['cheminContenu'] as String?,
        tailleSurDisque: octetsNom != null ? null : tailleSurDisque,
        compresse: x['compresse'] == true,
        sensible: x['sensible'] == true,
      ));
    }
    if (fichiers.isEmpty) return null;
    return PreparationEnCours._(
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
    );
  }

  Future<void> _oublier(PreparationEnCours p) async {
    _enCours.remove(p.id);
    CentreTransferts.instance.reussir(p.id);
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

  /// L'entrée du centre des transferts : c'est ELLE qui tient le service
  /// Android de premier plan, donc l'application en vie hors de l'écran.
  void _annoncer(PreparationEnCours p) {
    CentreTransferts.instance.demarrer(
      id: p.id,
      sorte: SorteTransfert.envoi,
      titre: _texte('envoi_compression'),
    );
  }

  void _avancer(PreparationEnCours p, double v) {
    final x = v.clamp(0.0, 1.0);
    p.avancement.value = x;
    CentreTransferts.instance.avancer(p.id, x);
  }

  bool _estPanneReseau(Object e) {
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

/// Un envoi qui attend la fin de la compression de ses vidéos.
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
  });

  /// Identifiant de la bulle « Compression… ».
  final String id;
  final String convId;

  /// Les fichiers tels qu'à l'appui sur Envoyer (originaux pour les vidéos).
  final List<MediaPickResult> fichiers;
  final String? legende;
  final List<Map<String, String>> mentions;
  final String? replyToId;
  final bool vueUnique;
  final bool chiffre;
  final String? pairId;
  final String? moi;
  final DateTime creeA;

  /// L'avancement de la compression, de 0 à 1 : l'anneau de la bulle.
  final ValueNotifier<double> avancement = ValueNotifier<double>(0);

  /// Le premier fichier : la vignette et le type de la bulle.
  MediaPickResult get premier => fichiers.first;

  String get msgType {
    final mime = premier.mimeType;
    if (mime.startsWith('image/')) return 'IMAGE';
    if (mime.startsWith('video/')) return 'VIDEO';
    if (mime.startsWith('audio/')) return 'AUDIO';
    return 'FILE';
  }

  bool _envoiEnCours = false;
  bool _attendReseau = false;
  List<MediaPickResult>? _prets;
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
