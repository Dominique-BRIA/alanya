import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/authed_api.dart';
import '../../core/server_config.dart';

/// UN STICKER du catalogue (`GET /api/stickers`).
class Sticker {
  const Sticker({
    required this.id,
    required this.assetId,
    required this.packCode,
    required this.emoji,
    required this.url,
    this.nom = const {},
    this.anime = false,
  });

  final int id;

  /// L'image : c'est elle que porte un message (`/api/stickers/fichier/<asset>`).
  final int assetId;
  final String packCode;
  final String emoji;
  final String url;

  /// Le nom par langue (`fr`, `en`, `zh`…), pour la recherche.
  final Map<String, String> nom;
  final bool anime;

  /// La charge d'un message STICKER — mêmes clés, même ordre que le serveur
  /// (`chargeSticker`, `message-payload.mjs`) et le web.
  String charge() => jsonEncode({
    'v': 1,
    'pack': packCode,
    'sid': id,
    'asset': assetId,
    'emoji': emoji,
    'w': 512,
    'h': 512,
    'a': anime ? 1 : 0,
  });

  static Sticker? depuisJson(Object? j, String packCode) {
    if (j is! Map) return null;
    final id = j['id'], asset = j['assetId'], url = j['url'];
    if (id is! int || asset is! int || url is! String) return null;
    return Sticker(
      id: id,
      assetId: asset,
      packCode: packCode,
      emoji: j['emoji'] is String ? j['emoji'] as String : '',
      url: url,
      nom: _traductions(j['nom']),
      anime: j['anime'] == true,
    );
  }
}

/// UN PACK publié par la console.
class PackStickers {
  const PackStickers({
    required this.id,
    required this.code,
    required this.nom,
    required this.stickers,
    this.description = const {},
    this.auteur,
    this.couverture,
  });

  final int id;
  final String code;
  final Map<String, String> nom;
  final Map<String, String> description;
  final String? auteur;
  final String? couverture;
  final List<Sticker> stickers;

  /// Le nom dans la langue de l'application, sinon l'anglais, sinon le français.
  String nomDans(String langue) => _dans(nom, langue) ?? code;
  String? descriptionDans(String langue) => _dans(description, langue);

  /// La vignette du pack : sa couverture, sinon son premier sticker.
  String? get vignette =>
      couverture ?? (stickers.isEmpty ? null : stickers.first.url);

  static PackStickers? depuisJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], code = j['code'];
    if (id is! int || code is! String) return null;
    final stickers = <Sticker>[
      for (final s in (j['stickers'] as List? ?? const []))
        if (Sticker.depuisJson(s, code) case final Sticker st) st,
    ];
    return PackStickers(
      id: id,
      code: code,
      nom: _traductions(j['nom']),
      description: _traductions(j['description']),
      auteur: j['auteur'] is String ? j['auteur'] as String : null,
      couverture: j['couverture'] is String ? j['couverture'] as String : null,
      stickers: stickers,
    );
  }
}

Map<String, String> _traductions(Object? brut) => {
  if (brut is Map)
    for (final e in brut.entries)
      if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
        e.key as String: e.value as String,
};

String? _dans(Map<String, String> t, String langue) =>
    t[langue] ?? t['en'] ?? t['fr'] ?? (t.isEmpty ? null : t.values.first);

/// Ce que porte un message STICKER (charge JSON), lu avec indulgence : une
/// version inconnue ou un champ manquant donne `null`, et la bulle dit
/// « Sticker » au lieu d'afficher du JSON.
class ChargeSticker {
  const ChargeSticker({
    required this.sid,
    required this.assetId,
    required this.pack,
    this.emoji = '',
  });

  final int sid;
  final int assetId;
  final String pack;
  final String emoji;

  /// L'image, lisible sans jeton (un sticker publié est public).
  String get url => '${ServerConfig.apiBase}/api/stickers/fichier/$assetId';

  static ChargeSticker? lire(String? content) {
    if (content == null || content.isEmpty) return null;
    try {
      final j = jsonDecode(content);
      if (j is! Map || j['v'] != 1) return null;
      final sid = j['sid'], asset = j['asset'], pack = j['pack'];
      if (sid is! int || asset is! int || pack is! String) return null;
      return ChargeSticker(
        sid: sid,
        assetId: asset,
        pack: pack,
        emoji: j['emoji'] is String ? j['emoji'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// LES STICKERS (24/10/2026, demande du user : « comme WhatsApp »).
///
/// * le CATALOGUE (`GET /api/stickers`) : ce que la console a publié ;
/// * MON PANNEAU (`GET /api/stickers/me`) : mes packs, dans mon ordre, et mes
///   favoris — communs à mes appareils, mobile et web ;
/// * les RÉCENTS : sur cet appareil seulement, comme WhatsApp.
///
/// Fermés par la console ([ouverts] faux), les stickers disparaissent de
/// l'application : pas d'onglet, pas de boutique. Les messages déjà reçus,
/// eux, s'affichent toujours (leur image reste servie).
///
/// Le dernier catalogue est gardé sur l'appareil : le panneau s'ouvre plein
/// même hors ligne, puis se met à jour.
///
/// ⚠️ UN PANNEAU PAR COMPTE ([suivreCompte]) : deux comptes se relaient sur
/// le même téléphone (constaté le 24/10/2026) ; l'un ne doit voir ni les
/// packs, ni les favoris, ni les récents de l'autre.
class StickersService extends ChangeNotifier {
  StickersService(this._api);

  final AuthedApi _api;

  static const _cleCatalogue = 'stickers_catalogue';
  static const maxRecents = 30;

  String? _compte;
  String get _cleMoi => 'stickers_moi_${_compte ?? '-'}';
  String get _cleRecents => 'stickers_recents_${_compte ?? '-'}';

  /// Le compte connecté a changé : on oublie le panneau du précédent.
  void suivreCompte(String? compte) {
    if (compte == _compte) return;
    _compte = compte;
    _charge = false;
    mesPacks = const [];
    favoris = const [];
    recents = const [];
    creation = false;
    creations = null;
    notifyListeners();
  }

  bool ouverts = false;
  List<PackStickers> catalogue = const [];

  /// Les identifiants de MES packs, dans l'ordre du panneau.
  List<int> mesPacks = const [];

  /// Mes favoris, le plus récent d'abord.
  List<int> favoris = const [];

  /// Les derniers envoyés depuis cet appareil, le plus récent d'abord.
  List<int> recents = const [];

  /// La console permet-elle de CRÉER ses stickers (25/10/2026) ?
  bool creation = false;

  /// « Mes créations » : mon pack personnel, la plus récente d'abord ; `null`
  /// tant que je n'ai rien créé.
  PackStickers? creations;

  bool _charge = false;
  Future<void>? _enCours;

  /// Charge une fois (et rend la même attente aux appels simultanés).
  Future<void> assurer() =>
      _charge ? Future.value() : (_enCours ??= _charger().whenComplete(() => _enCours = null));

  /// Recharge depuis le serveur (retour dans la boutique, par exemple).
  Future<void> rafraichir() => _enCours ??= _charger().whenComplete(() => _enCours = null);

  Future<void> _charger() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!_charge) {
        mesPacks = const [];
        favoris = const [];
        _lireCatalogue(prefs.getString(_cleCatalogue));
        _lireMoi(prefs.getString(_cleMoi));
        recents = [
          for (final s in prefs.getStringList(_cleRecents) ?? const <String>[])
            if (int.tryParse(s) case final int id) id,
        ];
        notifyListeners();
      }
    } catch (_) {}
    try {
      final cat = await _api.get('/api/stickers');
      _lireCatalogue(jsonEncode(cat));
      unawaited(prefs?.setString(_cleCatalogue, jsonEncode(cat)));
      if (ouverts) {
        final moi = await _api.get('/api/stickers/me');
        _lireMoi(jsonEncode(moi));
        unawaited(prefs?.setString(_cleMoi, jsonEncode(moi)));
      }
      _charge = true;
      notifyListeners();
    } catch (e) {
      // Hors ligne : on garde ce qui était en mémoire ou sur l'appareil.
      debugPrint('[stickers] chargement impossible : $e');
    }
  }

  void _lireCatalogue(String? brut) {
    if (brut == null) return;
    try {
      final j = jsonDecode(brut) as Map;
      ouverts = j['enabled'] == true;
      catalogue = [
        for (final p in (j['packs'] as List? ?? const []))
          if (PackStickers.depuisJson(p) case final PackStickers pk) pk,
      ];
    } catch (_) {}
  }

  void _lireMoi(String? brut) {
    if (brut == null) return;
    try {
      final j = jsonDecode(brut) as Map;
      mesPacks = [
        for (final p in (j['packs'] as List? ?? const []))
          if (p is Map && p['id'] is int) p['id'] as int,
      ];
      favoris = [
        for (final f in (j['favorites'] as List? ?? const []))
          if (f is int) f,
      ];
      final features = j['features'];
      creation = features is Map && features['creation'] == true;
      creations = PackStickers.depuisJson(j['created']);
    } catch (_) {}
  }

  // ── Lecture ─────────────────────────────────────────────────────────────

  PackStickers? pack(int id) {
    for (final p in catalogue) {
      if (p.id == id) return p;
    }
    return null;
  }

  PackStickers? packParCode(String code) {
    for (final p in catalogue) {
      if (p.code == code) return p;
    }
    return null;
  }

  Sticker? sticker(int id) {
    for (final p in [...catalogue, ?creations]) {
      for (final s in p.stickers) {
        if (s.id == id) return s;
      }
    }
    return null;
  }

  /// Un sticker de MES créations ?
  bool estMaCreation(int id) =>
      creations?.stickers.any((s) => s.id == id) ?? false;

  /// Mes packs, dans l'ordre du panneau (ceux qui existent encore).
  List<PackStickers> get packsInstalles => [
    for (final id in mesPacks)
      if (pack(id) case final PackStickers p) p,
  ];

  bool estInstalle(int packId) => mesPacks.contains(packId);
  bool estFavori(int stickerId) => favoris.contains(stickerId);

  List<Sticker> get stickersFavoris => [
    for (final id in favoris)
      if (sticker(id) case final Sticker s) s,
  ];

  List<Sticker> get stickersRecents => [
    for (final id in recents)
      if (sticker(id) case final Sticker s) s,
  ];

  /// La recherche de WhatsApp : par émoji ou par nom, toutes langues.
  List<Sticker> chercher(String requete) {
    final q = requete.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final p in [?creations, ...packsInstalles])
        for (final s in p.stickers)
          if (s.emoji.contains(q) ||
              s.nom.values.any((n) => n.toLowerCase().contains(q)))
            s,
    ];
  }

  // ── Écriture ────────────────────────────────────────────────────────────
  //
  // ⚠️ L'ÉCRAN CHANGE TOUT DE SUITE, le serveur suit : un échec remet l'état
  // d'avant et relève l'erreur à l'appelant.

  Future<void> installer(int packId) async {
    if (estInstalle(packId)) return;
    final avant = mesPacks;
    mesPacks = [...mesPacks, packId];
    notifyListeners();
    try {
      await _api.put('/api/stickers/me/packs/$packId', const {});
      unawaited(_memoriserMoi());
    } catch (e) {
      mesPacks = avant;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> retirer(int packId) async {
    final avant = mesPacks;
    mesPacks = mesPacks.where((id) => id != packId).toList();
    notifyListeners();
    try {
      await _api.delete('/api/stickers/me/packs/$packId');
      unawaited(_memoriserMoi());
    } catch (e) {
      mesPacks = avant;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> ordonner(List<int> ids) async {
    final avant = mesPacks;
    mesPacks = ids;
    notifyListeners();
    try {
      await _api.put('/api/stickers/me/packs/order', {'ids': ids});
      unawaited(_memoriserMoi());
    } catch (e) {
      mesPacks = avant;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> basculerFavori(int stickerId) async {
    final ajout = !estFavori(stickerId);
    final avant = favoris;
    favoris = ajout
        ? [stickerId, ...favoris]
        : favoris.where((id) => id != stickerId).toList();
    notifyListeners();
    try {
      if (ajout) {
        await _api.put('/api/stickers/me/favorites/$stickerId', const {});
      } else {
        await _api.delete('/api/stickers/me/favorites/$stickerId');
      }
      unawaited(_memoriserMoi());
    } catch (e) {
      favoris = avant;
      notifyListeners();
      rethrow;
    }
  }

  // ── Créer ses stickers (25/10/2026) ───────────────────────────────────────

  /// Crée un sticker à partir d'une image PNG (le cadre capturé par l'écran
  /// de création) ; il entre en tête de « Mes créations ». Rend le sticker.
  Future<Sticker> creer(Uint8List png, {String emoji = ''}) async {
    final r = await _api.uploadBytes(
      '/api/stickers/assets',
      png,
      'sticker.png',
      'image/png',
      fields: {if (emoji.isNotEmpty) 'emoji': emoji},
    );
    await _relireMoi();
    final cree = sticker(r['stickerId'] as int);
    if (cree == null) throw StateError('Sticker créé introuvable');
    return cree;
  }

  /// Retire une de mes créations. Son image reste dans les messages envoyés.
  Future<void> supprimerCreation(int id) async {
    final avant = creations;
    final avantFavoris = favoris;
    if (avant != null) {
      creations = PackStickers(
        id: avant.id,
        code: avant.code,
        nom: avant.nom,
        stickers: avant.stickers.where((s) => s.id != id).toList(),
      );
      favoris = favoris.where((f) => f != id).toList();
      notifyListeners();
    }
    try {
      await _api.delete('/api/stickers/stickers/$id');
      unawaited(_memoriserMoi());
    } catch (e) {
      creations = avant;
      favoris = avantFavoris;
      notifyListeners();
      rethrow;
    }
  }

  /// Garde dans « Mes créations » un sticker reçu (celui d'un autre).
  Future<void> copier(int stickerId) async {
    await _api.post('/api/stickers/stickers/$stickerId/copy', const {});
    await _relireMoi();
  }

  /// Signale l'image d'un sticker reçu à la modération.
  Future<void> signaler(int assetId) =>
      _api.post('/api/stickers/signalements', {'assetId': assetId, 'motif': 'inapproprie'});

  Future<void> _relireMoi() async {
    final moi = await _api.get('/api/stickers/me');
    _lireMoi(jsonEncode(moi));
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleMoi, jsonEncode(moi));
    } catch (_) {}
  }

  /// Après un envoi : le sticker passe en tête des récents de cet appareil.
  Future<void> noterRecent(int stickerId) async {
    recents = [
      stickerId,
      ...recents.where((id) => id != stickerId),
    ].take(maxRecents).toList();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cleRecents, [for (final id in recents) '$id']);
    } catch (_) {}
  }

  Future<void> _memoriserMoi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cleMoi,
        jsonEncode({
          'packs': [for (final id in mesPacks) {'id': id}],
          'favorites': favoris,
          'features': {'creation': creation},
          if (creations case final PackStickers c)
            'created': {
              'id': c.id,
              'code': c.code,
              'nom': c.nom,
              'stickers': [
                for (final st in c.stickers)
                  {
                    'id': st.id,
                    'assetId': st.assetId,
                    'emoji': st.emoji,
                    'nom': st.nom,
                    'url': st.url,
                    'anime': st.anime,
                  },
              ],
            },
        }),
      );
    } catch (_) {}
  }
}
