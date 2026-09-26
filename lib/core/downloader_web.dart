// ignore: deprecated_member_use
import 'dart:html' as html;

/// Miroir de la signature native — voir `downloader_io.dart`.
///
/// ⚠️ Le navigateur ne rapporte AUCUNE progression ici : c'est LUI qui
/// télécharge, via son propre gestionnaire, et il l'affiche déjà à sa façon.
/// Le paramètre existe pour que les appelants soient identiques sur les deux
/// plateformes ; il n'est jamais appelé.
typedef SurProgression = void Function(double? fraction);

/// ⚠️ Rend `String?` comme la version native, et non `void` : les appelants
/// comparent le retour à `null` pour distinguer réussite et échec. Une
/// signature divergente compilait tant que le web n'était pas bâti, et aurait
/// cassé le premier build web sur du code qui n'a rien à voir.
Future<String?> downloadUrl(String url, String filename,
    {SurProgression? surProgression}) async {
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..target = "_blank"
    ..style.display = "none";
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Le navigateur gère le fichier lui-même : nous n'avons aucun chemin à rendre,
  // mais l'action a bien abouti.
  return filename;
}

Future<String?> downloadOnly(String url, String filename,
        {SurProgression? surProgression}) =>
    downloadUrl(url, filename);

Future<void> openLocalFile(String path) async {}

Future<String?> getCachedFile(String filename) async => null;

Future<String?> downloadToCache(String url, String filename,
        {SurProgression? surProgression}) async =>
    null;
