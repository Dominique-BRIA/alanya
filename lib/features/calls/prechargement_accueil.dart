import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/server_config.dart';
import '../../core/token_storage.dart';
import 'repondeur_repository.dart';

/// L'ACCUEIL DU RÉPONDEUR, TÉLÉCHARGÉ PENDANT QUE ÇA SONNE.
///
/// 🔴 CE MODULE EXISTE POUR UNE SEULE RAISON : QUE L'ACCUEIL SE JOUE TOUT SEUL,
/// tout de suite, sans qu'on ait à toucher « Écouter l'accueil ».
///
/// La feuille jouait l'accueil depuis son ADRESSE RÉSEAU. Au moment précis où
/// il faut du son, on lançait donc une requête : le temps de la résoudre, de
/// l'authentifier et de recevoir les premiers octets, la feuille restait
/// muette — et sur un réseau lent elle le restait longtemps. On croyait à un
/// bouton qui ne marche pas.
///
/// Un appel sonne trente secondes. Ce temps était perdu : on attendait, PUIS on
/// téléchargeait. Menés ensemble, le fichier est là AVANT qu'on en ait besoin,
/// et la lecture part d'un FICHIER LOCAL — aucune latence, aucun jeton, aucun
/// refus possible.
///
/// ⚠️ LE TÉLÉCHARGEMENT S'ANNULE DÈS QU'IL N'A PLUS D'OBJET — on décroche, on
/// raccroche. Sans cela, on paierait les données d'un accueil que personne
/// n'entendra, sur un forfait mobile, à chaque appel abouti.
class PrechargementAccueil {
  PrechargementAccueil._();
  static final PrechargementAccueil instance = PrechargementAccueil._();

  String? _callId;
  Completer<String?>? _attente;
  http.Client? _client;
  String? _fichier;

  /// Le fichier dont la feuille s'est saisie : il ne doit plus être effacé par
  /// une annulation, sous peine de la laisser sans son.
  String? _adopte;

  /// Commence à télécharger l'accueil de la personne appelée.
  ///
  /// [urlDirecte] court-circuite la demande au serveur : en mode absence, la
  /// trame `repondeur_direct` porte déjà l'adresse, et redemander serait un
  /// aller-retour de plus pour une réponse qu'on a sous la main.
  ///
  /// ⚠️ NE LÈVE JAMAIS. Un préchargement qui échoue n'est pas une panne : on
  /// retombe sur l'adresse réseau, exactement comme avant. Le laisser remonter
  /// ferait échouer le DÉCLENCHEMENT du répondeur pour un gain de confort.
  /// [depot] n'est demandé que pour le cas par défaut, où l'adresse de
  /// l'accueil doit être réclamée au serveur. Il est fourni par l'appelant
  /// plutôt que construit ici : il porte la session authentifiée, qui vit dans
  /// l'arbre de l'application et n'a pas à être dupliquée dans un singleton.
  void demarrer(String callId, {String? urlDirecte, RepondeurRepository? depot}) {
    if (_callId == callId) return;
    annuler();

    _callId = callId;
    final attente = Completer<String?>();
    _attente = attente;
    final client = http.Client();
    _client = client;

    unawaited(() async {
      try {
        var relative = urlDirecte;
        if (relative == null && depot != null) {
          final accueil = await depot.accueilDeLAppel(callId);
          relative = accueil?.url;
        }
        if (relative == null || relative.isEmpty) {
          if (!attente.isCompleted) attente.complete(null);
          return;
        }

        final jeton = await TokenStorage().accessToken;
        final url = relative.startsWith("http")
            ? relative
            : "${ServerConfig.apiBase}$relative"
                "${(jeton == null || jeton.isEmpty) ? "" : "?token=$jeton"}";

        final reponse = await client.get(Uri.parse(url));
        if (reponse.statusCode != 200 || reponse.bodyBytes.isEmpty) {
          if (!attente.isCompleted) attente.complete(null);
          return;
        }

        // ⚠️ DANS LE CACHE, PAS DANS LES DOCUMENTS. Un accueil est jetable :
        // il ne doit ni survivre à l'appel, ni apparaître dans les fichiers de
        // l'utilisateur, ni compter dans la sauvegarde du téléphone.
        final dossier = await getTemporaryDirectory();
        final chemin = "${dossier.path}/accueil-$callId.audio";
        await File(chemin).writeAsBytes(reponse.bodyBytes, flush: true);

        // L'appel a pu changer entre-temps : on ne garde pas un fichier qui n'a
        // plus de destinataire.
        if (_callId != callId) {
          unawaited(_effacer(chemin));
          if (!attente.isCompleted) attente.complete(null);
          return;
        }
        _fichier = chemin;
        if (!attente.isCompleted) attente.complete(chemin);
      } catch (e) {
        debugPrint("[Alanya] préchargement de l'accueil abandonné : $e");
        if (!attente.isCompleted) attente.complete(null);
      } finally {
        client.close();
      }
    }());
  }

  /// Attend l'accueil préchargé, sans jamais attendre indéfiniment.
  ///
  /// ⚠️ [maximum] N'EST PAS UNE PRÉCAUTION DE PRINCIPE. Sur un réseau lent, un
  /// accueil de deux mégaoctets peut mettre une minute : sans plafond, la
  /// tonalité jouerait tout ce temps et l'appelant croirait que ça sonne
  /// encore. Passé le délai, on rend `null` et l'on retombe sur l'adresse
  /// réseau — la feuille paraît, et le bouton « Écouter l'accueil » reste la
  /// sortie de secours.
  Future<String?> attendre(String callId, Duration maximum) async {
    if (_callId != callId || _attente == null) return null;
    final chemin = await _attente!.future
        .timeout(maximum, onTimeout: () => null)
        .catchError((_) => null);
    if (chemin == null) return null;

    /*
     * ⚠️ LE FICHIER CHANGE DE MAIN ICI. La feuille va le jouer, et l'appel se
     * termine dans la foulée — or terminer annule le préchargement, ce qui
     * effacerait le fichier sous les pieds de la feuille. En le sortant du
     * préchargement, il survit jusqu'à `libererAdopte`.
     */
    await libererAdopte();
    _adopte = chemin;
    if (_callId == callId) {
      _callId = null;
      _attente = null;
      _fichier = null;
    }
    return chemin;
  }

  /// Arrête et oublie le préchargement en cours.
  ///
  /// Appelé quand l'appel aboutit ou qu'on raccroche : il n'y aura pas de
  /// répondeur, et continuer à télécharger serait payer pour rien.
  void annuler() {
    _callId = null;
    _attente = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    final chemin = _fichier;
    _fichier = null;
    if (chemin != null) unawaited(_effacer(chemin));
  }

  /// Efface le fichier que la feuille utilisait.
  ///
  /// Sans cela, chaque appel manqué laisserait son accueil dans le cache — une
  /// poignée de mégaoctets à chaque fois, que rien ne viendrait jamais reprendre.
  Future<void> libererAdopte() async {
    final chemin = _adopte;
    _adopte = null;
    if (chemin != null) await _effacer(chemin);
  }

  Future<void> _effacer(String chemin) async {
    try {
      final f = File(chemin);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
