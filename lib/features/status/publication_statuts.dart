import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' show ClientException;
import 'package:video_compress/video_compress.dart';

import '../../core/api_client.dart';
import '../../core/centre_transferts.dart';
import '../../core/connectivity_service.dart';
import '../../core/compression_video.dart';
import '../../core/media_cache.dart';
import '../media/media_repository.dart';
import 'screens/editeur_media_statut_screen.dart' show MediaEdite;
import 'status_repository.dart';
import 'statuts_persistes.dart';

/// PUBLIE LES STATUTS EN ARRIÈRE-PLAN.
///
/// 🔴 POURQUOI CE SERVICE EXISTE (retour device du 04/09/2026). La publication
/// se faisait DANS l'écran de composition : il fallait le regarder tourner
/// jusqu'au bout, et l'indicateur s'affichait sur le bouton d'envoi du statut
/// TEXTE — celui de l'écran resté derrière. Quitter l'application pendant le
/// transcodage d'une vidéo perdait l'envoi.
///
/// Désormais l'écran se ferme immédiatement et l'envoi continue ici, comme sur
/// WhatsApp.
///
/// ⚠️ AUCUN `BuildContext`, jamais. Ce service survit à l'écran qui l'a
/// démarré — en garder un mènerait à écrire dans un arbre démonté. Même règle
/// que `CentreTransferts` et `EnvoiMediaStore`.
///
/// 🔴 C'EST `CentreTransferts` QUI TIENT LE PROCESSUS ÉVEILLÉ, et c'est tout
/// l'intérêt de passer par lui plutôt que de lancer un `Future` détaché :
/// `ServiceTransferts` démarre le service Android de premier plan dès qu'un
/// transfert est déclaré. Sans ça, Android suspend puis tue l'application dès
/// qu'on la quitte, et l'envoi meurt avec elle.
class PublicationStatuts {
  PublicationStatuts._();
  static final PublicationStatuts instance = PublicationStatuts._();

  /// La file : les publications s'enchaînent, jamais en parallèle.
  ///
  /// ⚠️ CE N'EST PAS UN CONFORT. `video_compress` refuse un second transcodage
  /// pendant le premier (il lève un `StateError`), et deux téléversements
  /// simultanés sur un réseau mobile se ralentissent l'un l'autre. Une file
  /// rend aussi l'ordre d'arrivée des statuts prévisible.
  Future<void> _file = Future.value();

  /// Combien de publications restent en cours — pour que la liste puisse le
  /// dire sans connaître le détail.
  int _enCours = 0;
  int get enCours => _enCours;

  /// Appelé après chaque publication réussie, pour rafraîchir la liste.
  void Function()? surPublication;

  /// Appelé quand un statut se met à attendre le réseau, ou repart.
  void Function()? surAttente;

  MediaRepository? _media;
  StatusRepository? _statuts;
  ConnectivityService? _conn;
  bool _restaure = false;
  bool _reprise = false;

  /// Branche le réseau et REPREND les statuts qui attendaient.
  ///
  /// 🔴 APPELÉ AU DÉMARRAGE DE L'APPLICATION. Sans lui, un statut relu du disque
  /// ne repartirait jamais : la reprise a besoin des dépôts, et ceux-ci
  /// n'arrivaient jusqu'ici qu'au moment où un écran publiait. Or après un
  /// redémarrage, personne ne publie — c'est justement le cas à résoudre.
  ///
  /// ⚠️ Aucun `BuildContext` : ce sont des objets construits une fois dans
  /// `main.dart`, comme pour `EnvoiMediaStore`.
  Future<void> brancher({
    required MediaRepository media,
    required StatusRepository statuts,
    required ConnectivityService conn,
  }) async {
    _media = media;
    _statuts = statuts;
    if (!identical(conn, _conn)) {
      _conn?.removeListener(_auRetourDuReseau);
      _conn = conn;
      conn.addListener(_auRetourDuReseau);
    }
    if (_restaure) return;
    _restaure = true;
    _auRetourDuReseau();
  }

  /// L'ECHEC VIENT-IL DU RESEAU, ou le serveur a-t-il REFUSE ?
  ///
  /// ⚠️ `ApiException` ne signifie que « le serveur a répondu ≥400 » — c'est le
  /// seul cas où `api_client` la lève. Une coupure remonte telle quelle. On ne
  /// traite pas pour autant n'importe quelle exception comme une panne : une
  /// erreur de programmation prise pour une coupure ferait réessayer sans fin.
  bool _estPanneReseau(Object e) {
    if (e is ApiException) return false;
    return e is SocketException || e is ClientException || e is TimeoutException;
  }

  /// Le réseau est revenu : ce qui attendait repart, dans l'ordre.
  void _auRetourDuReseau() {
    final conn = _conn;
    final media = _media;
    final statuts = _statuts;
    if (conn == null || media == null || statuts == null) return;
    if (!conn.isOnline || _reprise) return;
    _reprise = true;

    _enfiler(() async {
      try {
        final attente = await StatutsPersistes.charger();
        for (final s in attente) {
          if (!conn.isOnline) break;
          await _televerserEtDeclarer(
            id: s.id,
            octets: s.octets,
            nom: s.nomFichier,
            mime: s.mimeType,
            durationMs: s.durationMs,
            legende: s.legende,
            mediaDeja: s.mediaId,
            creeA: s.creeA,
            media: media,
            statuts: statuts,
            // ⚠️ Pas de transcodage ici : les octets rangés sont ceux d'APRÈS.
            // La progression occupe donc toute la barre, et non sa seconde
            // moitié.
            partTranscodage: 0,
          );
        }
      } finally {
        _reprise = false;
      }
    });
    surAttente?.call();
  }

  /// Publie un statut TEXTE, sans faire attendre l'écran.
  ///
  /// 🔴 IL PASSE PAR LA MÊME FILE QUE LES MÉDIAS (demande du user, 04/09/2026 :
  /// « j'espère que le chargement au niveau du bouton d'envoi a été réglé même
  /// pour les statuts texte »). Une seule requête suffit pourtant à le
  /// publier — mais sur un réseau mobile lent, cette requête bloquait quand
  /// même le bouton d'envoi, et un texte perdu parce qu'on a quitté l'écran
  /// est aussi désagréable qu'une vidéo perdue.
  ///
  /// ⚠️ IL N'OUVRE PAS DE TRANSFERT. Un texte part en une fraction de seconde :
  /// afficher une notification de progression pour ça ferait clignoter la
  /// barre système sans rien apprendre à personne. En cas d'échec, en revanche,
  /// il faut le dire — d'où [surEchec].
  void publierTexte(
    String texte,
    String couleur, {
    required StatusRepository statuts,
    void Function()? surEchec,
  }) {
    _enfiler(() async {
      try {
        await statuts.createText(texte, couleur);
        surPublication?.call();
      } catch (_) {
        surEchec?.call();
      }
    });
  }

  /// Publie [medias], un statut par média, dans l'ordre.
  void publierMedias(
    List<MediaEdite> medias, {
    required MediaRepository media,
    required StatusRepository statuts,
  }) {
    for (final m in medias) {
      _enfiler(() => _publierUn(m, media: media, statuts: statuts));
    }
  }

  void _enfiler(Future<void> Function() travail) {
    _enCours++;
    // On enchaîne sur la file EXISTANTE : `catchError` garde la file vivante
    // même quand une publication échoue, sinon un seul échec bloquerait toutes
    // les suivantes.
    _file = _file.then((_) => travail()).catchError((_) {});
    _file = _file.whenComplete(() {
      if (_enCours > 0) _enCours--;
    });
  }

  Future<void> _publierUn(
    MediaEdite m, {
    required MediaRepository media,
    required StatusRepository statuts,
  }) async {
    final estVideo = m.mimeType.startsWith('video/');
    final id = 'statut-${DateTime.now().microsecondsSinceEpoch}';
    final centre = CentreTransferts.instance;
    centre.demarrer(
      id: id,
      sorte: SorteTransfert.envoi,
      titre: estVideo ? "Statut vidéo" : "Statut photo",
    );

    StreamSubscription<void>? _;
    var octets = m.octets;
    var nom = m.nomFichier;
    var mime = m.mimeType;

    try {
      if (estVideo) {
        // Le transcodage occupe la première moitié de la barre, l'envoi la
        // seconde : une seule progression pour l'utilisateur, qui ne sait pas
        // — et n'a pas à savoir — qu'il y a deux étapes.
        final abonnement = VideoCompress.compressProgress$.subscribe((p) {
          centre.avancer(id, (p / 100) * 0.5);
        });
        try {
          final v = await compresserVideo(
            m.octets,
            chemin: m.chemin,
            nomFichier: m.nomFichier,
            mimeType: m.mimeType,
          );
          octets = v.octets;
          nom = v.nomFichier;
          mime = v.mimeType;
        } finally {
          abonnement.unsubscribe();
        }
      }

      await _televerserEtDeclarer(
        id: id,
        octets: octets,
        nom: nom,
        mime: mime,
        durationMs: m.durationMs,
        legende: m.legende,
        mediaDeja: null,
        creeA: DateTime.now(),
        media: media,
        statuts: statuts,
        partTranscodage: estVideo ? 0.5 : 0,
      );
      return;
    } catch (_) {
      // Le transcodage a échoué : rien n'a encore quitté l'appareil, et ce n'est
      // pas une affaire de réseau.
      centre.echouer(id);
      return;
    }
  }

  /// Téléverse les octets puis déclare le statut. Utilisé au premier essai comme
  /// à la reprise après une coupure.
  ///
  /// [mediaDeja] est renseigné quand le téléversement avait déjà abouti et que
  /// seule la déclaration a échoué : les octets ne repartent alors pas.
  Future<void> _televerserEtDeclarer({
    required String id,
    required Uint8List octets,
    required String nom,
    required String mime,
    required int? durationMs,
    required String? legende,
    required String? mediaDeja,
    required DateTime creeA,
    required MediaRepository media,
    required StatusRepository statuts,
    required double partTranscodage,
  }) async {
    final centre = CentreTransferts.instance;
    String? idMedia = mediaDeja;
    try {
      if (idMedia == null) {
        final envoye = await media.upload(
          octets,
          nom,
          mime,
          durationMs: durationMs,
          onProgress: (envoyes, total) {
            if (total <= 0) return;
            final part = envoyes / total;
            centre.avancer(
                id, partTranscodage + part * (1 - partTranscodage));
          },
        );
        idMedia = envoye.id;

      /*
       * 🔴 LE CACHE EST SEMÉ AVEC LES OCTETS QU'ON A DÉJÀ EN MAIN.
       *
       * Sans ça, rouvrir SON PROPRE statut le retéléchargeait entièrement —
       * défaut signalé sur device le 04/09/2026. Les octets viennent d'être
       * envoyés depuis ce téléphone : les redemander au serveur est une
       * dépense de données pure.
       *
       * ⚠️ LA CLÉ DOIT ÊTRE CELLE QUE `CachedMedia.cacheKey` CALCULERA pour
       * `/api/media/<id>` — c'est-à-dire le dernier segment, donc l'identifiant
       * seul. Et l'extension `dat`, celle qu'utilise `loadCachedMediaBytes`.
       * Une clé qui ne coïncide pas ne casse rien : elle ne sert simplement à
       * personne, et le téléchargement recommence.
       */
        try {
          await MediaCache.put(idMedia, 'dat', octets);
        } catch (_) {
          // Un cache qui échoue ne doit pas faire échouer une publication.
        }
      }

      await statuts.createMedia(
        idMedia,
        mime.startsWith('video/') ? 'VIDEO' : 'IMAGE',
        legende: legende,
      );
      centre.reussir(id);
      await StatutsPersistes.oublier(id);
      surPublication?.call();
    } catch (e) {
      if (_estPanneReseau(e)) {
        /*
         * 🔴 PAS DE RÉSEAU N'EST PAS UN ÉCHEC — c'est une attente.
         *
         * L'écran marquait le transfert en échec : une ligne rouge dans la barre
         * système, à balayer à la main, et la photo perdue. Il fallait la
         * reprendre, la recadrer, la réannoter.
         *
         * ⚠️ `reussir` ET NON `echouer` : il ne s'agit pas de mentir sur le
         * résultat, mais de RETIRER la notification sans la marquer en rouge.
         * Elle reparaîtra d'elle-même quand le statut repartira.
         *
         * ⚠️ L'IDENTIFIANT DE MÉDIA EST RANGÉ S'IL A ÉTÉ OBTENU : les octets ne
         * repartiront pas une seconde fois, et aucun média orphelin ne restera
         * en base.
         */
        await StatutsPersistes.enregistrer(
          id: id,
          octets: octets,
          nomFichier: nom,
          mimeType: mime,
          durationMs: durationMs,
          legende: legende,
          mediaId: idMedia,
          creeA: creeA,
        );
        centre.reussir(id);
        surAttente?.call();
        return;
      }
      // ⚠️ L'entrée est CONSERVÉE, marquée échouée : la retirer laisserait une
      // notification d'échec orpheline. Même règle que les transferts.
      centre.echouer(id);
      await StatutsPersistes.oublier(id);
    }
  }
}
