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
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;

  static String get _defaultBaseUrl => ServerConfig.apiBase;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final res = await http.post(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path, {String? bearer}) async {
    final res = await http.get(Uri.parse("$baseUrl$path"), headers: _headers(bearer));
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final res = await http.patch(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(String path,
      {String? bearer, Map<String, dynamic>? body}) async {
    final res = await http.delete(
      Uri.parse("$baseUrl$path"),
      headers: _headers(bearer),
      body: body != null ? jsonEncode(body) : null,
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
