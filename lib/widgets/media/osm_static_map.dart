import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/media_cache.dart';
import '../../theme/alanya_theme.dart';

/// Carte statique centrée sur un point, composée de tuiles.
///
/// POURQUOI À LA MAIN, sans paquet de cartographie : `flutter_map` ferait
/// exactement cela en beaucoup plus gros, et **ajouter un paquet, c'est toucher
/// à tous les environnements de build** — il y a trois CI dans ce projet, plus
/// le poste local, et une contrainte `environment:` incompatible casse le
/// `pub get` de l'un d'eux sans que rien ne le signale ici. Une carte figée
/// n'a besoin ni de gestes, ni de couches, ni de plugins : seulement de la
/// projection de Mercator et de quelques images.
///
/// **SOURCE DES TUILES : MapTiler, par clé injectée à la compilation.**
///
/// Les serveurs d'openstreetmap.org ont été écartés : leur politique d'usage
/// interdit qu'une application DISTRIBUÉE y prenne ses tuiles, et le prix d'un
/// blocage serait une carte grise chez tout le monde, sans avertissement.
///
/// 🔴 **LA CLÉ N'EST PAS DANS LE CODE, ET NE DOIT PAS Y ENTRER : les deux
/// dépôts de ce projet sont PUBLICS** (vérifié le 17/08/2026 via l'API GitHub).
/// Une clé poussée sur un dépôt public est ramassée par des robots en quelques
/// minutes, et c'est le quota du user qui se vide. Elle est donc fournie au
/// build :
///
///     flutter build apk --dart-define=MAPTILER_KEY=<clé>
///
/// et vient d'un secret de CI (voir les trois fichiers de CI du dépôt).
///
/// ⚠️ **Sans clé, il n'y a PAS de repli sur OpenStreetMap** — c'était le
/// comportement à éviter : un build qui oublie la variable aurait produit une
/// application en infraction, et personne ne l'aurait vu. La carte retombe sur
/// une vignette sobre, qui reste utile (repère + coordonnées + ouverture dans
/// l'application de cartes) et qui SE VOIT.
///
/// ⚠️ **Une clé de carte embarquée dans une application est extractible de
/// l'APK** : c'est vrai de toutes les applications mobiles qui affichent une
/// carte, et aucun réglage de compilation n'y change rien. La vraie protection
/// est côté MapTiler — restreindre les origines autorisées et surveiller le
/// quota.
class OsmStaticMap extends StatelessWidget {
  const OsmStaticMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.width,
    required this.height,
    this.zoom = 15,
    this.marqueur = true,
  });

  final double lat;
  final double lng;
  final double width;
  final double height;
  final int zoom;
  final bool marqueur;

  /// Clé MapTiler, injectée à la compilation. Vide = pas de tuiles.
  static const String cleMapTiler = String.fromEnvironment("MAPTILER_KEY");

  /// Style de carte. Modifiable sans toucher au code (`basic-v2`, `topo-v2`…).
  static const String _style =
      String.fromEnvironment("MAPTILER_STYLE", defaultValue: "streets-v2");

  /// Vrai si l'application a été compilée avec une clé de cartes.
  static bool get tuilesDisponibles => cleMapTiler.isNotEmpty;

  /// ⚠️ Le segment `/256/` n'est pas décoratif : sans lui MapTiler sert des
  /// tuiles de **512 px**, et toute la projection de cette classe (qui place
  /// les images au pixel près) serait décalée d'un facteur deux. Vérifié par
  /// requête réelle : 256 → 37 Ko, sans le segment → 71 Ko.
  String _urlTuile(int z, int x, int y) =>
      "https://api.maptiler.com/maps/$_style/256/$z/$x/$y.png?key=$cleMapTiler";

  /// Nom de la tuile sur le disque.
  ///
  /// ⚠️ **La clé n'entre PAS dans ce nom**, alors qu'elle est dans l'URL : une
  /// rotation de clé jetterait sinon tout le cache, alors que l'image est
  /// exactement la même. Le style, lui, en fait partie — deux styles donnent
  /// deux images pour les mêmes coordonnées.
  String _cleCache(int z, int x, int y) => "tuile_${_style}_${z}_${x}_$y";

  /// Identifie l'application auprès du fournisseur de tuiles.
  static const Map<String, String> entetes = {
    "User-Agent": "AlanyaWork/0.1 (com.alanya237.work)",
  };

  static const double _tuile = 256;

  static double _xMonde(double lon, int z) =>
      (lon + 180.0) / 360.0 * _tuile * (1 << z);

  static double _yMonde(double lat, int z) {
    // Mercator : la latitude n'est pas linéaire. Bornée à ±85,05° — au-delà, la
    // projection part à l'infini (et il n'y a pas de tuiles aux pôles).
    final borne = lat.clamp(-85.05112878, 85.05112878);
    final rad = borne * pi / 180.0;
    return (1 - log(tan(rad) + 1 / cos(rad)) / pi) / 2 * _tuile * (1 << z);
  }

  @override
  Widget build(BuildContext context) {
    final centreX = _xMonde(lng, zoom);
    final centreY = _yMonde(lat, zoom);

    // Coin haut-gauche de la fenêtre, en pixels monde.
    final origineX = centreX - width / 2;
    final origineY = centreY - height / 2;

    const tuileMin = 0;
    final tuileMax = (1 << zoom) - 1;
    final xDebut = (origineX / _tuile).floor();
    final yDebut = (origineY / _tuile).floor();
    final xFin = ((origineX + width) / _tuile).floor();
    final yFin = ((origineY + height) / _tuile).floor();

    final images = <Widget>[];
    // Sans clé de cartes, on n'affiche AUCUNE tuile — et surtout pas celles
    // d'OpenStreetMap en repli (voir l'en-tête de classe). La vignette sobre
    // qui reste porte le repère, les coordonnées, et ouvre l'application de
    // cartes : elle est utile, et son aspect signale qu'il manque la clé.
    for (var tx = xDebut; tuilesDisponibles && tx <= xFin; tx++) {
      for (var ty = yDebut; ty <= yFin; ty++) {
        // Hors du monde en latitude : il n'existe aucune tuile, on laisse le
        // fond. En longitude, on enroule (le monde est un cylindre).
        if (ty < tuileMin || ty > tuileMax) continue;
        final txEnroule = tx % (1 << zoom);
        final x = (txEnroule < 0 ? txEnroule + (1 << zoom) : txEnroule);
        images.add(Positioned(
          left: tx * _tuile - origineX,
          top: ty * _tuile - origineY,
          width: _tuile,
          height: _tuile,
          child:
              _Tuile(url: _urlTuile(zoom, x, ty), cle: _cleCache(zoom, x, ty)),
        ));
      }
    }

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fond visible tant que les tuiles chargent, et sous les trous.
            Container(color: const Color(0xFFE8E4DC)),
            ...images,
            if (marqueur)
              Center(
                child: Padding(
                  // La pointe du repère doit tomber SUR le point, pas son
                  // centre : on le remonte de la moitié de sa hauteur.
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Icon(Icons.location_pin,
                      size: 36,
                      color: const Color(0xFFEF4444),
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1)),
                      ]),
                ),
              ),
            // Attribution : exigée par MapTiler ET par la licence des données
            // OpenStreetMap dont ses fonds dérivent. Elle n'apparaît que
            // lorsqu'une carte est réellement affichée — l'écrire sur une
            // vignette sans tuile créditerait une donnée absente.
            if (tuilesDisponibles)
              Positioned(
                right: 3,
                bottom: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  color: Colors.white.withValues(alpha: 0.7),
                  child: const Text("© MapTiler © OpenStreetMap",
                      style: TextStyle(fontSize: 7, color: AlanyaColors.ink)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Une tuile, servie depuis le DISQUE quand elle y est déjà.
///
/// POURQUOI : le quota MapTiler du palier gratuit se compte en requêtes
/// (100 000 par mois). `Image.network` ne garde ses images qu'en MÉMOIRE, et
/// Flutter vide ce cache dès qu'il manque de place : remonter une conversation
/// où traînent trois positions retéléchargeait leurs tuiles à chaque passage.
/// Le même carré de carte pouvait donc être payé dix fois dans la journée.
///
/// Avec le disque, une tuile est téléchargée UNE FOIS par téléphone. Et comme
/// on partage souvent sa position depuis les mêmes endroits — bureau, domicile,
/// boutique —, les mêmes tuiles reviennent d'un message à l'autre : c'est le
/// cas où un cache rapporte le plus.
///
/// ⚠️ Pas de purge par ancienneté : une tuile pèse ~30 Ko, il en faudrait
/// plusieurs milliers pour que cela pèse. `MediaCache.clear()` les efface avec
/// le reste si le besoin s'en fait sentir.
class _Tuile extends StatefulWidget {
  const _Tuile({required this.url, required this.cle});

  final String url;
  final String cle;

  @override
  State<_Tuile> createState() => _TuileState();
}

class _TuileState extends State<_Tuile> {
  String? _chemin;

  @override
  void initState() {
    super.initState();
    _charge();
  }

  @override
  void didUpdateWidget(_Tuile ancien) {
    super.didUpdateWidget(ancien);
    // La liste recycle ses widgets : sans cela, une tuile garderait l'image de
    // la position précédente en changeant de message.
    if (ancien.cle != widget.cle) {
      _chemin = null;
      _charge();
    }
  }

  Future<void> _charge() async {
    try {
      final chemin = await MediaCache.getOrFetch(
        mediaId: widget.cle,
        ext: 'png',
        fetchNetwork: () async {
          final res = await http
              .get(Uri.parse(widget.url), headers: OsmStaticMap.entetes)
              .timeout(const Duration(seconds: 15));
          // ⚠️ Une clé invalide répond 403 AVEC une image d'erreur dans le
          // corps. Sans ce contrôle, ce carré « unauthorized » serait écrit sur
          // le disque et s'afficherait POUR TOUJOURS, même une fois la clé
          // corrigée — un cache ne se trompe qu'une fois, mais durablement.
          if (res.statusCode != 200) {
            throw HttpException('tuile ${res.statusCode}');
          }
          return res.bodyBytes;
        },
      );
      if (mounted) setState(() => _chemin = chemin);
    } catch (_) {
      // Tuile indisponible : le fond neutre reste, et le repère par-dessus dit
      // toujours où on est.
    }
  }

  @override
  Widget build(BuildContext context) {
    final chemin = _chemin;
    if (chemin == null) return const SizedBox.shrink();
    return Image.file(
      File(chemin),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
