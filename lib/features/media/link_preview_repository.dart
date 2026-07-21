import '../../core/authed_api.dart';
import '../../core/media_helper.dart';

/// Récupère les métadonnées OpenGraph d'un lien.
class LinkPreviewRepository {
  LinkPreviewRepository(this._api);
  final AuthedApi _api;

  final Map<String, LinkMeta> _cache = {};

  Future<LinkMeta?> fetch(String url) async {
    // Cache local
    if (_cache.containsKey(url)) return _cache[url];

    try {
      final data = await _api.get('/api/link-preview', query: {'url': url});
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
      return null;
    }
  }

  void clearCache() => _cache.clear();
}
