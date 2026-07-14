/// Point d'entrée multiplateforme pour télécharger/ouvrir une URL de média.
/// Sélectionne l'implémentation web (dart:html) ou native (dart:io) à la compilation.
export 'downloader_io.dart' if (dart.library.html) 'downloader_web.dart';
