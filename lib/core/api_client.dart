import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'cache_ecrans.dart';
import 'locale_controller.dart';
import 'maintenance.dart';
import 'server_config.dart';

/// Exception levée quand l'API renvoie une erreur (status >= 400).
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  ApiException(this.statusCode, this.message, [this.code]);

  @override
  String toString() => message;
}

/// Requête multipart qui annonce sa progression.
///
/// POURQUOI UNE SOUS-CLASSE, et pas un paquet : `http.MultipartRequest.send()`
/// n'expose aucun compteur, et c'est la seule raison pour laquelle l'envoi d'un
/// média n'avait aucune barre de progression. Passer à `dio` pour ce seul besoin
/// signifierait ajouter un paquet — donc toucher aux TROIS chaînes de CI de ce
/// projet, pour une fonctionnalité qui tient en dix lignes. `finalize()` rend le
/// corps sous forme de flux : il suffit de compter ce qui y passe.
class _RequeteMultipartSuivie extends http.MultipartRequest {
  _RequeteMultipartSuivie(super.method, super.url, {this.onProgress});

  final void Function(int envoyes, int total)? onProgress;

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var envoyes = 0;
    final flux = super.finalize();
    return http.ByteStream(
      flux.transform(StreamTransformer.fromHandlers(
        handleData: (List<int> donnees, EventSink<List<int>> sortie) {
          envoyes += donnees.length;
          onProgress?.call(envoyes, total);
          sortie.add(donnees);
        },
      )),
    );
  }
}

/// Client HTTP minimal vers le backend Alanya (Next.js).
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;

  /// Le temps au bout duquel on cesse d'attendre une reponse.
  ///
  /// 🔴 C'EST LA CAUSE DU CHARGEMENT INFINI SIGNALE. `package:http` N'A AUCUN
  /// DELAI PAR DEFAUT : une requete dont la reponse n'arrive jamais — reseau
  /// coupe apres l'etablissement, serveur qui ne repond plus, portail wifi qui
  /// avale la connexion — attend INDEFINIMENT. Le `Future` ne se termine ni en
  /// succes ni en erreur, donc le `catch` de l'appelant ne s'execute jamais et
  /// son indicateur de chargement reste vrai pour toujours.
  ///
  /// ⚠️ UN `try/catch` NE PROTEGE PAS D'UNE ATTENTE SANS FIN. Il n'attrape que
  /// ce qui est leve ; une attente qui ne revient pas ne leve rien. Le seul
  /// remede est un delai, et il doit vivre ICI — pas dans chaque ecran, sinon
  /// il manquera partout ou l'on aura oublie de le mettre.
  ///
  /// ⚠️ NE S'APPLIQUE PAS AUX ENVOIS DE MEDIAS. Televerser une video de dix
  /// megaoctets depasse legitimement trente secondes ; les couper serait
  /// transformer une lenteur normale en echec.
  static const Duration delaiReponse = Duration(seconds: 30);

  static String get _defaultBaseUrl => ServerConfig.apiBase;

  // ══════════════════════════════════════════════
  // COPIES LOCALES (cache d'abord) — 18/10/2026
  // ══════════════════════════════════════════════
  /*
   * 🐛 « CERTAINS ÉCRANS METTENT DU TEMPS À OUVRIR » (user, 18/10/2026) : les
   * sous-écrans des Paramètres attendaient le serveur, roue au milieu, avant
   * d'afficher quoi que ce soit.
   *
   * 🔴 LE MÉCANISME VIT ICI, UNE FOIS — comme sur CETIC (`Api.copieSeulement`) :
   * la réponse d'un GET des [cheminsGardes] est gardée sur le téléphone ; un
   * écran relit ensuite cette copie en appelant SA PROPRE fonction de
   * chargement dans [copieSeulement]. Aucun dépôt n'a de second format à
   * maintenir.
   */

  /// Les GET dont la réponse est gardée — des réglages et des listes courtes,
  /// jamais des messages ni des médias.
  static const cheminsGardes = <String>[
    '/api/account/privacy',
    '/api/user-access',
    '/api/blocked',
    '/api/repondeur',
    '/api/repondeur/plages',
    '/api/pays',
    '/api/ringtones',
    '/api/appareils',
  ];

  static bool _aGarder(String path) {
    final sansRequete = path.split('?').first;
    return cheminsGardes.contains(sansRequete);
  }

  static const _cleCopieSeule = #alanyaCopieSeule;

  /// Vrai pendant un [copieSeulement] : le réseau est interdit.
  static bool get enCopieSeule => Zone.current[_cleCopieSeule] == true;

  /// Exécute [lecture] en ne servant QUE les copies gardées sur le téléphone,
  /// sans aucun appel réseau ni aucune écriture. Échoue s'il manque une copie.
  static Future<R> copieSeulement<R>(Future<R> Function() lecture) =>
      runZoned(lecture, zoneValues: {_cleCopieSeule: true});

  static Never _pasDeCopie() => throw ApiException(0, 'Pas de copie locale.');

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    if (enCopieSeule) _pasDeCopie();
    final res = await http.post(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: jsonEncode(body),
    ).timeout(delaiReponse, onTimeout: _expire);
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path, {String? bearer}) async {
    final cle = 'api$path';
    if (enCopieSeule) {
      if (!_aGarder(path)) _pasDeCopie();
      final copie = await CacheEcrans.lire(cle);
      if (copie is! Map) _pasDeCopie();
      return Map<String, dynamic>.from(copie);
    }
    final res = await http
        .get(Uri.parse("$baseUrl$path"), headers: _headers(bearer))
        .timeout(delaiReponse, onTimeout: _expire);
    final data = _decode(res);
    if (_aGarder(path)) unawaited(CacheEcrans.ecrire(cle, data));
    return data;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    if (enCopieSeule) _pasDeCopie();
    final res = await http.patch(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: jsonEncode(body),
    ).timeout(delaiReponse, onTimeout: _expire);
    return _decode(res);
  }

  /// PUT — REMPLACE la ressource, là où `patch` la modifie en partie.
  ///
  /// La distinction n'est pas cosmétique : l'audience des statuts envoie son
  /// état complet (mode + liste), et c'est ce qui rend l'enregistrement
  /// rejouable. Un PATCH aurait laissé croire à un envoi partiel.
  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    if (enCopieSeule) _pasDeCopie();
    final res = await http.put(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: jsonEncode(body),
    ).timeout(delaiReponse, onTimeout: _expire);
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(String path,
      {String? bearer, Map<String, dynamic>? body}) async {
    if (enCopieSeule) _pasDeCopie();
    final res = await http.delete(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: body != null ? jsonEncode(body) : null,
    ).timeout(delaiReponse, onTimeout: _expire);
    return _decode(res);
  }

  /// Upload multipart d'un fichier (champ "file"), avec champs additionnels optionnels.
  ///
  /// [onProgress] reçoit (octets envoyés, octets total) au fil de l'émission.
  ///
  /// ⚠️ **Ce que la progression mesure vraiment** : les octets remis à la pile
  /// réseau, pas ceux que le serveur a reçus. Sur un petit fichier, elle peut
  /// donc atteindre 100 % alors que la réponse n'est pas encore là — c'est la
  /// limite de tout indicateur d'envoi côté client, et la raison pour laquelle
  /// l'interface doit distinguer « 100 % » de « terminé » : seul le retour de
  /// cette fonction dit que le média existe côté serveur.
  Future<Map<String, dynamic>> uploadBytes(
    String path,
    Uint8List bytes,
    String filename,
    String mimeType, {
    String? bearer,
    Map<String, String>? fields,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final request = _RequeteMultipartSuivie(
      "POST",
      Uri.parse("$baseUrl$path"),
      onProgress: onProgress,
    );
    if (bearer != null) request.headers["Authorization"] = "Bearer $bearer";
    request.headers["Accept-Language"] = LocaleController.codeCourant;
    if (fields != null) request.fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes(
      "file",
      bytes,
      filename: filename,
      contentType: MediaType.parse(mimeType),
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  /// Comme [uploadBytes], mais lit le fichier EN FLUX depuis le disque plutôt
  /// que de le charger entièrement en mémoire.
  ///
  /// 🔴 **POURQUOI.** Un enregistrement d'appel non compressé pèse ~11 Mo par
  /// minute ; un appel de 30 min tenu en `Uint8List` (comme le fait
  /// [uploadBytes]) menace l'OOM. `MultipartFile.fromPath` envoie le fichier
  /// morceau par morceau, sans jamais le tenir en entier — c'est la seule voie
  /// tenable pour un flux dont on ne borne pas la durée.
  Future<Map<String, dynamic>> uploadFile(
    String path,
    String filePath,
    String filename,
    String mimeType, {
    String? bearer,
    Map<String, String>? fields,
    void Function(int envoyes, int total)? onProgress,
  }) async {
    final request = _RequeteMultipartSuivie(
      "POST",
      Uri.parse("$baseUrl$path"),
      onProgress: onProgress,
    );
    if (bearer != null) request.headers["Authorization"] = "Bearer $bearer";
    request.headers["Accept-Language"] = LocaleController.codeCourant;
    if (fields != null) request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath(
      "file",
      filePath,
      filename: filename,
      contentType: MediaType.parse(mimeType),
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  /// Ce que l'on rend quand le delai est ecoule.
  ///
  /// ⚠️ ON LEVE UNE `ApiException`, PAS UNE `TimeoutException`. Tout l'appli
  /// sait deja traiter la premiere ; la seconde serait un type de plus a
  /// attraper dans chaque ecran, et on en oublierait.
  static Never _expire() =>
      throw ApiException(408, "Le serveur n'a pas repondu a temps.");

  /// ⚠️ `Accept-Language` porte la langue CHOISIE DANS L'APPLICATION : le
  /// serveur écrit les courriels dans cette langue. Sans lui, un code
  /// d'inscription demandé en russe arrivait en français.
  Map<String, String> _headers(String? bearer) => {
        "Content-Type": "application/json",
        "Accept-Language": LocaleController.codeCourant,
        if (bearer != null) "Authorization": "Bearer $bearer",
      };

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> data = {};
    try {
      if (res.body.isNotEmpty) {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // body non-JSON (ex. HTML d'erreur Vercel)
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode, "Erreur serveur ${res.statusCode}");
      }
    }
    if (res.statusCode >= 400) {
      // Format backend : { error: { message, code } }
      final err = data["error"] as Map<String, dynamic>?;
      final msg = (err?["message"] as String?)
          ?? (data["message"] as String?)
          ?? "Erreur ${res.statusCode}";
      final code = err?["code"] as String?;
      // Le serveur est en maintenance : l'écran d'attente prend le relais.
      if (res.statusCode == 503 && code == "MAINTENANCE") Maintenance.signaler();
      throw ApiException(res.statusCode, msg, code);
    }
    return data;
  }
}
