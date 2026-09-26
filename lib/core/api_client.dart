import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

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
  ApiClient({String? baseUrl, Duration? delaiReponse})
      : baseUrl = baseUrl ?? _defaultBaseUrl,
        delaiReponse = delaiReponse ?? delaiJson;

  final String baseUrl;

  /// Plafond d'attente des requêtes JSON de CETTE instance.
  ///
  /// ⚠️ PARAMÉTRABLE POUR ÊTRE ÉPROUVABLE. Un test ne peut pas attendre trente
  /// secondes pour vérifier qu'une attente est bornée : il raccourcit le délai
  /// et mesure. Le défaut reste [delaiJson], le seul que l'application utilise.
  final Duration delaiReponse;

  static String get _defaultBaseUrl => ServerConfig.apiBase;

  /// Au-delà, une requête JSON est réputée perdue.
  ///
  /// 🔴 **SANS CETTE BORNE, UNE REQUÊTE QUI N'ABOUTIT PAS BLOQUE L'ÉCRAN POUR
  /// TOUJOURS.** `package:http` n'applique AUCUN délai : une connexion TCP
  /// acceptée mais jamais servie — relais qui avale les paquets, serveur figé,
  /// changement de réseau en plein vol — laisse le `Future` en suspens
  /// indéfiniment. L'écran de conversation, qui attend cette réponse pour
  /// remplacer son cercle de chargement, tournait alors sans fin : c'est
  /// exactement le symptôme « ça charge indéfiniment ».
  ///
  /// ⚠️ 30 s N'EST PAS UN DÉLAI DE PATIENCE, C'EST UNE BORNE DE DIAGNOSTIC. Une
  /// requête JSON met quelques centaines de millisecondes ; trois secondes sont
  /// déjà un incident. Trente laissent passer un réseau mobile lent sans
  /// transformer une lenteur en panne, et rendent la main au bouton
  /// « Réessayer » au lieu d'un cercle éternel.
  static const delaiJson = Duration(seconds: 30);

  /// Applique [delaiReponse] à une requête et traduit l'expiration en
  /// [ApiException] — pour que tous les écrans qui lisent déjà `e.message`
  /// l'affichent, au lieu de laisser une attente sans fin ni explication.
  ///
  /// ⚠️ LE CODE 408 EST SIGNIFICATIF : la session n'est PAS morte. Un délai
  /// dépassé ne doit jamais faire croire à une déconnexion — voir
  /// `sessionMorteApresEchec`, qui ne ferme la session que sur les codes du
  /// serveur, jamais sur celui-ci.
  ///
  /// ⚠️ **LES ENVOIS DE MÉDIAS NE PASSENT PAS PAR ICI, ET C'EST VOULU.** Un
  /// `uploadBytes` de 20 Mo sur un réseau mobile est LÉGITIMEMENT long : un
  /// délai TOTAL y couperait des envois qui progressent. Leur borne, c'est la
  /// progression elle-même — le magasin d'envois sait dire « bloqué » sur une
  /// absence de progrès, ce qu'un délai fixe ne sait pas faire.
  Future<T> _borne<T>(Future<T> requete, String methode, String path) {
    return requete.timeout(
      delaiReponse,
      onTimeout: () => throw ApiException(
        408,
        "Le serveur n'a pas répondu en ${delaiReponse.inMilliseconds} ms "
        "($methode $path).",
        'DELAI_DEPASSE',
      ),
    );
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final res = await _borne(
      http.post(
        Uri.parse("$baseUrl$path"),
        headers: _headers(bearer),
        body: jsonEncode(body),
      ),
      "POST",
      path,
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path, {String? bearer}) async {
    final res = await _borne(
      http.get(Uri.parse("$baseUrl$path"), headers: _headers(bearer)),
      "GET",
      path,
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final res = await _borne(
      http.patch(
        Uri.parse("$baseUrl$path"),
        headers: _headers(bearer),
        body: jsonEncode(body),
      ),
      "PATCH",
      path,
    );
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
    final res = await _borne(
      http.put(
        Uri.parse("$baseUrl$path"),
        headers: _headers(bearer),
        body: jsonEncode(body),
      ),
      "PUT",
      path,
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(String path,
      {String? bearer, Map<String, dynamic>? body}) async {
    final res = await _borne(
      http.delete(
        Uri.parse("$baseUrl$path"),
        headers: _headers(bearer),
        body: body != null ? jsonEncode(body) : null,
      ),
      "DELETE",
      path,
    );
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

  Map<String, String> _headers(String? bearer) => {
        "Content-Type": "application/json",
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
      throw ApiException(res.statusCode, msg, code);
    }
    return data;
  }
}
