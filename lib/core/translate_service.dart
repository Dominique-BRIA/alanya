import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service de traduction avec fallback
/// 1. LibreTranslate mirrors
/// 2. MyMemory (gratuit, sans clé)
class TranslateService {
  TranslateService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const List<String> _libreHosts = [
    'https://translate.argosopentech.com',
    'https://libretranslate.de',
    'https://translate.terraprint.co',
    'https://libretranslate.com', // en dernier, demande souvent une clé
  ];

  Future<String> translate({
    required String text,
    required String target,
    String source = 'auto',
    String? host,
    String? apiKey,
  }) async {
    // 1. Essaye LibreTranslate / mirrors
    final hosts = host != null ? [host] : _libreHosts;
    Exception? lastErr;
    for (final h in hosts) {
      try {
        return await _libreTranslate(text, target, source, h, apiKey);
      } catch (e) {
        lastErr = e is Exception ? e : Exception('$e');
        continue;
      }
    }
    // 2. Fallback MyMemory – gratuit, sans clé, fr <-> en OK
    try {
      return await _myMemoryTranslate(text, target, source);
    } catch (_) {}
    throw lastErr ?? Exception('Translation failed');
  }

  Future<String> _libreTranslate(String text, String target, String source, String host, String? apiKey) async {
    final endpoint = Uri.parse('$host/translate');
    final body = {
      'q': text,
      'source': source,
      'target': target,
      'format': 'text',
      if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
    };
    final res = await _client.post(endpoint, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('LibreTranslate $host: ${res.statusCode} ${res.body.substring(0, res.body.length > 120 ? 120 : res.body.length)}');
    final data = jsonDecode(res.body);
    final translated = data['translatedText'] as String?;
    if (translated == null || translated.isEmpty) throw Exception('Empty response');
    return translated;
  }

  Future<String> _myMemoryTranslate(String text, String target, String source) async {
    final src = source == 'auto' ? 'fr' : source;
    // MyMemory n'aime pas l'auto, on devine : si target==fr alors src=en sinon src=fr
    final effectiveSrc = source == 'auto' ? (target == 'fr' ? 'en' : 'fr') : source;
    final langpair = '$effectiveSrc|$target';
    final uri = Uri.https('api.mymemory.translated.net', '/get', {'q': text, 'langpair': langpair});
    final res = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('MyMemory ${res.statusCode}');
    final data = jsonDecode(res.body);
    final translated = data['responseData']?['translatedText'] as String?;
    if (translated == null) throw Exception('MyMemory empty');
    return translated;
  }

  void dispose() => _client.close();
}
