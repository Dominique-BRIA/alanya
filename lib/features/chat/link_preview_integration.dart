import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/media_helper.dart';

class LinkPreviewIntegration {
  LinkPreviewIntegration(this._baseUrl);
  final String _baseUrl;
  final Map<String, LinkMeta?> _cache = {};

  Future<LinkMeta?> fetch(String url) async {
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final uri = Uri.parse('$_baseUrl/api/link-preview')
          .replace(queryParameters: {'url': url});
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) { _cache[url] = null; return null; }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final meta = LinkMeta(
        url: data['url'] as String? ?? url,
        title: data['title'] as String?,
        description: data['description'] as String?,
        imageUrl: data['imageUrl'] as String?,
        siteName: data['siteName'] as String?,
        favicon: data['favicon'] as String?,
      );
      _cache[url] = meta;
      return meta;
    } catch (_) {
      _cache[url] = null;
      return null;
    }
  }
}
