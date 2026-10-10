import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Un enregistrement d'appel prêt à être déposé, décrit de façon à SURVIVRE à la
/// fermeture de l'application.
///
/// 🔴 Tout ce qu'il faut pour rejouer le dépôt à l'identique est ici, `cleEnvoi`
/// comprise : le serveur étant idempotent sur cette clé, un réessai après
/// coupure ou après un redémarrage de l'app ne crée jamais de doublon. C'est ce
/// qui transforme un « au mieux, à la fin de l'appel » en une livraison sûre.
@immutable
class EnregistrementEnAttente {
  const EnregistrementEnAttente({
    required this.cleEnvoi,
    required this.companyId,
    required this.cheminAgent,
    required this.cheminClient,
    required this.dureeMs,
    this.callId,
    this.tentatives = 0,
    this.mediaAgentId,
    this.mediaClientId,
  });

  final String cleEnvoi;
  final int companyId;
  final String cheminAgent;
  final String cheminClient;
  final int dureeMs;
  final String? callId;
  final int tentatives;

  /// Identifiants des médias DÉJÀ téléversés, mémorisés au fil des essais.
  ///
  /// 🔴 Sans eux, un réseau instable re-téléverserait à CHAQUE tentative un WAV
  /// de plusieurs dizaines de méga-octets et laisserait une traînée de médias
  /// orphelins. On les persiste dès qu'une piste est passée : la reprise ne
  /// renvoie plus que ce qui manque. Remis à nul sur un `MEDIA_NOT_FOUND` (le
  /// serveur a pu purger un orphelin entre deux essais).
  final String? mediaAgentId;
  final String? mediaClientId;

  EnregistrementEnAttente copyWith({
    int? tentatives,
    String? Function()? mediaAgentId,
    String? Function()? mediaClientId,
  }) => EnregistrementEnAttente(
    cleEnvoi: cleEnvoi,
    companyId: companyId,
    cheminAgent: cheminAgent,
    cheminClient: cheminClient,
    dureeMs: dureeMs,
    callId: callId,
    tentatives: tentatives ?? this.tentatives,
    mediaAgentId: mediaAgentId != null ? mediaAgentId() : this.mediaAgentId,
    mediaClientId: mediaClientId != null ? mediaClientId() : this.mediaClientId,
  );

  Map<String, dynamic> toJson() => {
    "cleEnvoi": cleEnvoi,
    "companyId": companyId,
    "cheminAgent": cheminAgent,
    "cheminClient": cheminClient,
    "dureeMs": dureeMs,
    "callId": callId,
    "tentatives": tentatives,
    "mediaAgentId": mediaAgentId,
    "mediaClientId": mediaClientId,
  };

  static EnregistrementEnAttente? fromJson(Map<String, dynamic> j) {
    final cle = j["cleEnvoi"];
    final company = j["companyId"];
    final agent = j["cheminAgent"];
    final client = j["cheminClient"];
    // Une entrée corrompue (champ manquant) est ignorée plutôt que de faire
    // échouer le chargement de TOUTE la file.
    if (cle is! String ||
        company is! int ||
        agent is! String ||
        client is! String) {
      return null;
    }
    return EnregistrementEnAttente(
      cleEnvoi: cle,
      companyId: company,
      cheminAgent: agent,
      cheminClient: client,
      dureeMs: j["dureeMs"] is int ? j["dureeMs"] as int : 0,
      callId: j["callId"] as String?,
      tentatives: j["tentatives"] is int ? j["tentatives"] as int : 0,
      mediaAgentId: j["mediaAgentId"] as String?,
      mediaClientId: j["mediaClientId"] as String?,
    );
  }
}

/// File PERSISTANTE des enregistrements en attente de dépôt.
///
/// 🔴 **POURQUOI SUR DISQUE, ET NON EN MÉMOIRE.** Un enregistrement déposé
/// « en fin d'appel » se perdait à la moindre coupure réseau, et l'app tuée
/// juste après emportait tout. Ici la liste est écrite dans un fichier JSON du
/// stockage privé : elle traverse un redémarrage, et au prochain lancement les
/// dépôts en attente reprennent. Les fichiers audio eux-mêmes vivent dans le
/// stockage PERSISTANT (pas le cache, qu'Android peut vider sous pression).
///
/// ⚠️ **Un seul écrivain à la fois.** Deux dépôts qui se terminent ensemble
/// réécriraient le fichier en même temps et l'un écraserait l'autre. Toutes les
/// opérations passent par un mutex maison (une chaîne de `Future`) — pas de
/// dépendance ajoutée pour dix lignes.
class EnregistrementsEnAttente {
  EnregistrementsEnAttente._();
  static final EnregistrementsEnAttente instance = EnregistrementsEnAttente._();

  static const _nomFichier = "enregistrements_attente.json";
  File? _fichier;

  // Mutex : chaque opération attend la précédente. `Future.value()` amorce la
  // chaîne pour que la toute première n'ait rien à attendre.
  Future<void> _chaine = Future.value();

  Future<T> _verrou<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final precedent = _chaine;
    _chaine = completer.future;
    return precedent.then((_) => action()).whenComplete(completer.complete);
  }

  Future<File> _resoudreFichier() async {
    final existant = _fichier;
    if (existant != null) return existant;
    final dossier = await getApplicationSupportDirectory();
    final f = File("${dossier.path}/$_nomFichier");
    _fichier = f;
    return f;
  }

  Future<List<EnregistrementEnAttente>> _lireSansVerrou() async {
    try {
      final f = await _resoudreFichier();
      if (!await f.exists()) return [];
      final texte = await f.readAsString();
      if (texte.trim().isEmpty) return [];
      final brut = jsonDecode(texte);
      if (brut is! List) return [];
      return brut
          .whereType<Map<String, dynamic>>()
          .map(EnregistrementEnAttente.fromJson)
          .whereType<EnregistrementEnAttente>()
          .toList();
    } catch (e) {
      debugPrint("[EnregistrementsEnAttente] lecture : $e");
      return [];
    }
  }

  Future<void> _ecrireSansVerrou(List<EnregistrementEnAttente> liste) async {
    final f = await _resoudreFichier();
    await f.writeAsString(
      jsonEncode(liste.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// Snapshot des entrées en attente, la plus ancienne d'abord.
  Future<List<EnregistrementEnAttente>> charger() => _verrou(_lireSansVerrou);

  /// Ajoute une entrée. Si sa `cleEnvoi` est déjà présente, ne fait rien —
  /// une même fin d'appel rejouée n'entasse pas deux fois le même dépôt.
  Future<void> ajouter(EnregistrementEnAttente entree) => _verrou(() async {
    final liste = await _lireSansVerrou();
    if (liste.any((e) => e.cleEnvoi == entree.cleEnvoi)) return;
    liste.add(entree);
    await _ecrireSansVerrou(liste);
  });

  /// Retire l'entrée d'une `cleEnvoi` (dépôt réussi, ou abandon définitif).
  Future<void> retirer(String cleEnvoi) => _verrou(() async {
    final liste = await _lireSansVerrou();
    final apres = liste.where((e) => e.cleEnvoi != cleEnvoi).toList();
    if (apres.length == liste.length) return;
    await _ecrireSansVerrou(apres);
  });

  /// Remplace une entrée (même `cleEnvoi`) par la version fournie — pour
  /// mémoriser un média déjà téléversé ou incrémenter le compteur d'essais.
  /// Ne fait rien si l'entrée n'existe plus (déposée entre-temps).
  Future<void> remplacer(EnregistrementEnAttente entree) => _verrou(() async {
    final liste = await _lireSansVerrou();
    var change = false;
    final apres = liste.map((e) {
      if (e.cleEnvoi != entree.cleEnvoi) return e;
      change = true;
      return entree;
    }).toList();
    if (change) await _ecrireSansVerrou(apres);
  });
}
