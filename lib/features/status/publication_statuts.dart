import 'dart:async';

import 'package:video_compress/video_compress.dart';

import '../../core/centre_transferts.dart';
import '../../core/compression_video.dart';
import '../../core/media_cache.dart';
import '../media/media_repository.dart';
import 'screens/editeur_media_statut_screen.dart' show MediaEdite;
import 'status_repository.dart';

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

      final envoye = await media.upload(
        octets,
        nom,
        mime,
        durationMs: m.durationMs,
        onProgress: (envoyes, total) {
          if (total <= 0) return;
          final part = envoyes / total;
          centre.avancer(id, estVideo ? 0.5 + part * 0.5 : part);
        },
      );

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
        await MediaCache.put(envoye.id, 'dat', octets);
      } catch (_) {
        // Un cache qui échoue ne doit pas faire échouer une publication.
      }

      await statuts.createMedia(
        envoye.id,
        mime.startsWith('video/') ? 'VIDEO' : 'IMAGE',
        legende: m.legende,
      );
      centre.reussir(id);
      surPublication?.call();
    } catch (_) {
      // ⚠️ L'entrée est CONSERVÉE, marquée échouée : la retirer laisserait une
      // notification d'échec orpheline. Même règle que les transferts.
      centre.echouer(id);
    }
  }
}
