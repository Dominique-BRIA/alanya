import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;

import 'decoupage_morceaux.dart';
import 'envoi_morceaux_api.dart';

/// CE QUI ARRIVE À UN MORCEAU, vu de l'application.
sealed class EvenementMorceau {
  const EvenementMorceau(this.envoiId, this.indice);
  final String envoiId;
  final int indice;
}

class MorceauAvance extends EvenementMorceau {
  const MorceauAvance(super.envoiId, super.indice, this.fraction);
  final double fraction;
}

/// Le serveur a accepté le morceau. [reponse] est le JSON qu'il a rendu : sur
/// le morceau qui termine l'envoi, il porte le média et la publication.
class MorceauRecu extends EvenementMorceau {
  const MorceauRecu(super.envoiId, super.indice, this.reponse);
  final String? reponse;
}

/// Le morceau a échoué pour de bon (réessais épuisés, ou refus du serveur).
class MorceauEchoue extends EvenementMorceau {
  const MorceauEchoue(super.envoiId, super.indice, this.statut, this.reponse);
  final int? statut;
  final String? reponse;
}

/// Qui pousse les morceaux. Deux réalisations : Android, en arrière-plan
/// ([TransportArrierePlan]) ; une requête HTTP directe ([TransportDirect]),
/// pour les tests contre un vrai serveur.
abstract class TransportMorceaux {
  Stream<EvenementMorceau> get evenements;

  /// Confie [morceaux] du fichier chiffré de [reservation], rangé sous le
  /// dossier des documents de l'application à [cheminRelatif].
  Future<void> confier(
    ReservationEnvoi reservation,
    String cheminRelatif,
    List<Morceau> morceaux, {
    required String titre,
  });

  /// Les morceaux de cet envoi qu'Android connaît encore (en file, en cours,
  /// en attente de réessai) — pour ne pas les confier deux fois à la reprise.
  Future<Set<int>> enVol(String envoiId);

  Future<void> annuler(String envoiId);
}

/// L'identifiant d'une tâche : `morceau|<envoi>|<n>`. Il suffit, à lui seul, à
/// retrouver l'envoi et le morceau quand Android rend compte, y compris après
/// un redémarrage où toute la mémoire de l'application a disparu.
String idTacheMorceau(String envoiId, int indice) => 'morceau|$envoiId|$indice';

({String envoiId, int indice})? lireIdTacheMorceau(String taskId) {
  final p = taskId.split('|');
  if (p.length != 3 || p[0] != 'morceau') return null;
  final n = int.tryParse(p[2]);
  return n == null ? null : (envoiId: p[1], indice: n);
}

String groupeEnvoi(String envoiId) => 'envoi|$envoiId';

/// LES MORCEAUX CONFIÉS À ANDROID (WorkManager), par `background_downloader`.
///
/// 🔴 TOUS LES MORCEAUX SONT CONFIÉS D'UN COUP, PENDANT QUE L'APPLICATION EST
/// AU PREMIER PLAN. WorkManager les range sur disque : ils survivent à la
/// fermeture de l'application, au balayage des tâches récentes, et même à un
/// redémarrage du téléphone. Il les envoie quand le réseau est là, quelques-uns
/// à la fois (son propre parallélisme, 3 à 4 selon le téléphone), et réessaie
/// chacun jusqu'à dix fois.
///
/// 🚫 PAS DE FILE D'ATTENTE NI DE TÂCHE « LANCÉE PAR L'UTILISATEUR » (Android
/// 14+). Une file qui confie le morceau suivant quand le précédent finit le
/// ferait alors que l'application est fermée — et Android refuse de
/// programmer ces tâches-là hors du premier plan. C'est précisément le cas
/// qu'on veut couvrir.
///
/// ⚠️ UN MORCEAU = 1 Mio : bien en dessous des neuf minutes qu'Android
/// accorde à une tâche de fond ordinaire, même sur un réseau très lent.
class TransportArrierePlan implements TransportMorceaux {
  TransportArrierePlan(this._base);

  final String _base;
  final _evenements = StreamController<EvenementMorceau>.broadcast();
  bool _demarre = false;

  @override
  Stream<EvenementMorceau> get evenements => _evenements.stream;

  /// À appeler UNE fois, au démarrage, AVANT toute reprise.
  ///
  /// ⚠️ `markDownloadedComplete: false` : par défaut, la bibliothèque marque
  /// « terminée » toute tâche dont le fichier existe — pensé pour les
  /// TÉLÉCHARGEMENTS. Pour un ENVOI, le fichier source existe toujours : chaque
  /// morceau en attente aurait été déclaré parti.
  Future<void> demarrer() async {
    if (_demarre) return;
    _demarre = true;
    FileDownloader().updates.listen(_surMiseAJour);
    await FileDownloader().start(markDownloadedComplete: false);
  }

  void _surMiseAJour(TaskUpdate u) {
    final id = lireIdTacheMorceau(u.task.taskId);
    if (id == null) return;
    switch (u) {
      case TaskProgressUpdate(:final progress):
        // Les valeurs négatives sont des codes (échec, annulation…), pas
        // une progression.
        if (progress >= 0 && progress <= 1) {
          _evenements.add(MorceauAvance(id.envoiId, id.indice, progress));
        }
      case TaskStatusUpdate(:final status, :final responseBody, :final responseStatusCode):
        if (status == TaskStatus.complete) {
          _evenements.add(MorceauRecu(id.envoiId, id.indice, responseBody));
        } else if (status == TaskStatus.failed || status == TaskStatus.notFound) {
          _evenements.add(MorceauEchoue(id.envoiId, id.indice, responseStatusCode, responseBody));
        }
    }
  }

  @override
  Future<void> confier(
    ReservationEnvoi reservation,
    String cheminRelatif,
    List<Morceau> morceaux, {
    required String titre,
  }) async {
    final groupe = groupeEnvoi(reservation.id);
    // UNE notification pour tout le fichier, et non une par morceau : deux
    // cents lignes « 1 Mio envoyé » ne diraient rien à personne.
    FileDownloader().configureNotificationForGroup(
      groupe,
      running: TaskNotification(titre, '{progress}'),
      complete: TaskNotification(titre, 'Envoyé'),
      error: const TaskNotification('Envoi interrompu', 'Ouvrez Alanya pour reprendre'),
      progressBar: true,
      groupNotificationId: groupe,
    );
    final dossier = cheminRelatif.substring(0, cheminRelatif.lastIndexOf('/'));
    final fichier = cheminRelatif.substring(cheminRelatif.lastIndexOf('/') + 1);
    for (final m in morceaux) {
      await FileDownloader().enqueue(UploadTask(
        taskId: idTacheMorceau(reservation.id, m.indice),
        url: '$_base/api/media/envois/${reservation.id}/morceaux/${m.indice}',
        filename: fichier,
        directory: dossier,
        baseDirectory: BaseDirectory.applicationDocuments,
        post: 'binary',
        httpRequestMethod: 'PUT',
        mimeType: 'application/octet-stream',
        headers: {
          'X-Envoi-Jeton': reservation.jeton,
          // Lu par la bibliothèque, NON transmis au serveur : seule cette
          // tranche du fichier part.
          'Range': m.plage,
          // Vide = en-tête omis : le nom du fichier n'a rien à faire là.
          'Content-Disposition': '',
        },
        group: groupe,
        updates: Updates.statusAndProgress,
        retries: 10,
        displayName: titre,
      ));
    }
  }

  @override
  Future<Set<int>> enVol(String envoiId) async {
    final taches = await FileDownloader()
        .allTasks(group: groupeEnvoi(envoiId), includeTasksWaitingToRetry: true);
    return {
      for (final t in taches)
        if (lireIdTacheMorceau(t.taskId) case final id?) id.indice,
    };
  }

  @override
  Future<void> annuler(String envoiId) =>
      FileDownloader().cancelAll(group: groupeEnvoi(envoiId));
}

/// Les morceaux envoyés directement, sans Android : pour les TESTS contre un
/// vrai serveur, et seulement pour eux. Application fermée, rien ne survit.
class TransportDirect implements TransportMorceaux {
  TransportDirect(this._base, this._racineDocuments, {this.enParallele = 3});

  final String _base;
  final String _racineDocuments;
  final int enParallele;
  final _evenements = StreamController<EvenementMorceau>.broadcast();
  final _enVol = <String, Set<int>>{};

  @override
  Stream<EvenementMorceau> get evenements => _evenements.stream;

  @override
  Future<void> confier(
    ReservationEnvoi reservation,
    String cheminRelatif,
    List<Morceau> morceaux, {
    required String titre,
  }) async {
    final chemin = '$_racineDocuments/$cheminRelatif';
    final vol = _enVol.putIfAbsent(reservation.id, () => {});
    vol.addAll(morceaux.map((m) => m.indice));
    final file = [...morceaux];
    Future<void> ouvrier() async {
      while (file.isNotEmpty) {
        final m = file.removeAt(0);
        final raf = await File(chemin).open();
        final octets = await (raf..setPositionSync(m.debut)).read(m.taille);
        await raf.close();
        final rep = await http.put(
          Uri.parse('$_base/api/media/envois/${reservation.id}/morceaux/${m.indice}'),
          headers: {'X-Envoi-Jeton': reservation.jeton, 'Content-Type': 'application/octet-stream'},
          body: octets,
        );
        vol.remove(m.indice);
        if (rep.statusCode < 300) {
          _evenements.add(MorceauRecu(reservation.id, m.indice, rep.body));
        } else {
          _evenements.add(MorceauEchoue(reservation.id, m.indice, rep.statusCode, rep.body));
        }
      }
    }

    // Lancés sans attendre, comme Android : l'appelant suit les événements.
    for (var i = 0; i < enParallele; i++) {
      unawaited(ouvrier());
    }
  }

  @override
  Future<Set<int>> enVol(String envoiId) async => {...?_enVol[envoiId]};

  @override
  Future<void> annuler(String envoiId) async => _enVol.remove(envoiId);
}
