import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart' show ApiException;
import '../../core/authed_api.dart';
import '../media/media_repository.dart';
import 'enregistrements_en_attente.dart';

/// Dépôt d'un enregistrement de conversation agent ↔ client, avec REPRISE.
///
/// ⚠️ Le contrat vit côté serveur (`src/app/api/call-recordings/route.ts`).
///
/// 🔴 **DEUX PISTES, PUIS LE SERVEUR MÉLANGE.** Le natif capte le micro et la
/// voix distante séparément (deux `AudioTrackSink` — voir `EnregistreurAppel`).
/// On téléverse donc les deux AAC, et le serveur les mixe.
///
/// 🔴 **LIVRAISON DURABLE.** L'ancienne version déposait « au mieux » à la fin de
/// l'appel : une coupure réseau, ou l'app tuée juste après, perdait
/// l'enregistrement pour de bon. Désormais chaque enregistrement est d'abord
/// inscrit dans une file PERSISTANTE ([EnregistrementsEnAttente]) ; le dépôt est
/// tenté, et **ce qui échoue reste en file** pour être repris — au prochain
/// raccrochage, ou au prochain démarrage de l'application. Les fichiers audio ne
/// sont effacés qu'une fois le serveur confirmé.
class EnregistrementsRepository {
  EnregistrementsRepository(this._api, this._medias);
  final AuthedApi _api;
  final MediaRepository _medias;

  final _attente = EnregistrementsEnAttente.instance;

  /// Au-delà, on renonce : un dépôt qui échoue des dizaines de fois ne réussira
  /// pas de lui-même, et garder ses fichiers indéfiniment remplirait le disque.
  /// À ~un essai par appel et par démarrage, la marge est large.
  static const _maxTentatives = 50;

  /// Empêche deux balayages concurrents (fin d'appel ET démarrage) de
  /// téléverser deux fois les mêmes fichiers.
  bool _enTraitement = false;

  /// Posé quand un dépôt est demandé pendant qu'un balayage tourne déjà : le
  /// balayage en cours refera un tour pour prendre la nouvelle entrée, au lieu
  /// de la laisser attendre le prochain déclencheur. N'est JAMAIS posé par un
  /// échec — donc pas de boucle serrée sur un dépôt qui rate.
  bool _redemander = false;

  /// Inscrit un enregistrement dans la file, puis lance un dépôt. La clé d'envoi
  /// est fabriquée UNE fois, ici : c'est elle qui rend les reprises idempotentes.
  ///
  /// ⚠️ N'attend pas le dépôt : l'appel est terminé, rien ni personne
  /// n'attend cette opération.
  Future<void> enfiler({
    String? callId,
    required int companyId,
    required String cheminAgent,
    required String cheminClient,
    required int dureeMs,
  }) async {
    await _attente.ajouter(
      EnregistrementEnAttente(
        cleEnvoi: _fabriquerCle(),
        companyId: companyId,
        cheminAgent: cheminAgent,
        cheminClient: cheminClient,
        dureeMs: dureeMs,
        callId: callId,
      ),
    );
    unawaited(traiterEnAttente());
  }

  /// Tente de déposer tout ce qui est en attente. Sûr à appeler en boucle :
  /// gardé contre la ré-entrée, et sans effet s'il n'y a rien.
  Future<void> traiterEnAttente() async {
    if (_enTraitement) {
      // Un balayage tourne déjà : qu'il refasse un tour à la fin plutôt que de
      // laisser cette nouvelle entrée attendre le prochain déclencheur.
      _redemander = true;
      return;
    }
    _enTraitement = true;
    try {
      do {
        _redemander = false;
        final entrees = await _attente.charger();
        for (final entree in entrees) {
          await _traiterUne(entree);
        }
      } while (_redemander);
    } catch (e) {
      debugPrint("[EnregistrementsRepository] balayage : $e");
    } finally {
      _enTraitement = false;
    }
  }

  Future<void> _traiterUne(EnregistrementEnAttente e) async {
    // Fichiers disparus (nettoyage manuel, réinstallation…) : rien à reprendre,
    // on abandonne proprement au lieu de réessayer sans fin.
    if (!await File(e.cheminAgent).exists() ||
        !await File(e.cheminClient).exists()) {
      debugPrint(
        "[EnregistrementsRepository] fichiers absents — abandon ${e.cleEnvoi}",
      );
      await _abandonner(e);
      return;
    }
    if (e.tentatives >= _maxTentatives) {
      debugPrint(
        "[EnregistrementsRepository] trop d'essais — abandon ${e.cleEnvoi}",
      );
      await _abandonner(e);
      return;
    }

    var courant = e;
    try {
      // Chaque piste n'est téléversée qu'une fois : son id est mémorisé dès
      // qu'elle passe, si bien qu'une reprise ne renvoie que ce qui manque.
      if (courant.mediaAgentId == null) {
        final m = await _medias.uploadFromFile(
          courant.cheminAgent,
          "appel-${courant.cleEnvoi}-agent.aac",
          "audio/aac",
          durationMs: courant.dureeMs,
        );
        courant = courant.copyWith(mediaAgentId: () => m.id);
        await _attente.remplacer(courant);
      }
      if (courant.mediaClientId == null) {
        final m = await _medias.uploadFromFile(
          courant.cheminClient,
          "appel-${courant.cleEnvoi}-client.aac",
          "audio/aac",
          durationMs: courant.dureeMs,
        );
        courant = courant.copyWith(mediaClientId: () => m.id);
        await _attente.remplacer(courant);
      }

      await _api.post("/api/call-recordings", {
        if (courant.callId != null) "callId": courant.callId,
        "companyId": courant.companyId,
        "mediaAgentId": courant.mediaAgentId,
        "mediaClientId": courant.mediaClientId,
        "dureeMs": courant.dureeMs,
        "cleEnvoi": courant.cleEnvoi,
      });
      // Déposé (ou déjà déposé : le serveur rend 200 sur `cleEnvoi` connue).
      await _reussir(courant);
    } on ApiException catch (ex) {
      if (ex.statusCode == 404) {
        // MEDIA_NOT_FOUND : un média mémorisé a été purgé côté serveur entre
        // deux essais. On oublie les ids et on re-téléversera au prochain tour.
        await _attente.remplacer(
          courant.copyWith(
            tentatives: courant.tentatives + 1,
            mediaAgentId: () => null,
            mediaClientId: () => null,
          ),
        );
      } else if (ex.statusCode == 403 ||
          ex.statusCode == 400 ||
          ex.statusCode == 422) {
        // Refus définitif (agent non autorisé, requête invalide) : réessayer ne
        // changera rien.
        debugPrint(
          "[EnregistrementsRepository] refus ${ex.statusCode} — abandon ${courant.cleEnvoi}",
        );
        await _abandonner(courant);
      } else {
        // 401 (session), 5xx, 429… : transitoire, on garde pour plus tard.
        await _attente.remplacer(
          courant.copyWith(tentatives: courant.tentatives + 1),
        );
      }
    } catch (ex) {
      // Réseau coupé, timeout : transitoire.
      debugPrint("[EnregistrementsRepository] dépôt ${courant.cleEnvoi} : $ex");
      await _attente.remplacer(
        courant.copyWith(tentatives: courant.tentatives + 1),
      );
    }
  }

  Future<void> _reussir(EnregistrementEnAttente e) async {
    await _attente.retirer(e.cleEnvoi);
    await _effacerFichiers(e);
  }

  Future<void> _abandonner(EnregistrementEnAttente e) async {
    await _attente.retirer(e.cleEnvoi);
    await _effacerFichiers(e);
  }

  Future<void> _effacerFichiers(EnregistrementEnAttente e) async {
    for (final chemin in [e.cheminAgent, e.cheminClient]) {
      try {
        final f = File(chemin);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  String _fabriquerCle() {
    final alea = Random();
    final suffixe = List.generate(
      8,
      (_) => alea.nextInt(36).toRadixString(36),
    ).join();
    return "ap-${DateTime.now().millisecondsSinceEpoch}-$suffixe";
  }
}
