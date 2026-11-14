import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// UNE SEULE RELÈVE À LA FOIS, TOUS ISOLATS CONFONDUS (14/11/2026).
///
/// Depuis la piste A, une notification réveille un isolat d'arrière-plan qui
/// relève les enveloppes pendant que l'application est fermée. Si l'écran
/// revient au même moment, deux relèves déchiffreraient les mêmes enveloppes
/// avec les mêmes sessions : la seconde verrait des messages « déjà lus », et
/// une session pourrait être effacée à tort.
///
/// ⚠️ PAS DE `File.lock` : sous Android, ce verrou est tenu par PROCESSUS, et
/// les deux isolats vivent dans le même. Un fichier créé en mode exclusif
/// (`O_EXCL`), lui, ne peut exister qu'une fois, quel que soit l'isolat.
///
/// ⚠️ UN VERROU ORPHELIN SE PÉRIME : un isolat tué par Android ne l'efface pas.
/// Au-delà de [peremption], il est repris.
class VerrouReleve {
  VerrouReleve._();

  static const peremption = Duration(seconds: 90);
  static const attenteMax = Duration(seconds: 60);

  static Future<File?> _fichier() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/releve_e2ee.verrou');
    } catch (_) {
      // Pas de répertoire (essais en Dart pur) : pas de verrou.
      return null;
    }
  }

  /// Exécute [action] sous le verrou. Sans verrou obtenu à temps, l'action
  /// part quand même : mieux vaut une relève qu'un message jamais affiché.
  static Future<T> sous<T>(Future<T> Function() action) async {
    final f = await _fichier();
    if (f == null) return action();
    final tenu = await _prendre(f);
    try {
      return await action();
    } finally {
      if (tenu) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  static Future<bool> _prendre(File f) async {
    final limite = DateTime.now().add(attenteMax);
    while (DateTime.now().isBefore(limite)) {
      try {
        await f.create(exclusive: true);
        return true;
      } on FileSystemException {
        try {
          final age = DateTime.now().difference(await f.lastModified());
          if (age > peremption) {
            await f.delete();
            continue;
          }
        } catch (_) {
          // Disparu entre-temps : on retente aussitôt.
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return false;
  }
}
