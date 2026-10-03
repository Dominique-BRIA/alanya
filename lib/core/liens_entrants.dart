import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'lien_alanya.dart';

/// LES LIENS ALANYA QUI OUVRENT L'APPLICATION (QR scanné par l'appareil photo,
/// lien reçu sur WhatsApp, Facebook…).
///
/// Android les confie à l'application grâce au filtre d'intention du manifeste
/// et à `https://alanyavox.com/.well-known/assetlinks.json`.
///
/// 🔴 ABONNEMENT DÈS LE LANCEMENT, CONSOMMATION PLUS TARD. `app_links` ne
/// rejoue le lien de démarrage qu'au PREMIER abonné, une seule fois, et un
/// lien qui arrive sans abonné est perdu pour le flux. Or l'écran qui sait
/// quoi en faire (l'accueil) n'existe qu'une fois connecté, et il est
/// démonté puis remonté à chaque changement de langue. On s'abonne donc dans
/// `main()`, et le lien attend ici qu'on vienne le [prendre].
///
/// Un seul lien en attente : le dernier ouvert remplace le précédent, qui
/// n'a plus de sens pour l'utilisateur.
class LiensEntrants {
  LiensEntrants._();
  static final instance = LiensEntrants._();

  final _enAttente = ValueNotifier<CibleLien?>(null);
  StreamSubscription<Uri>? _abonnement;

  /// Le lien reçu et pas encore traité ; notifie à chaque arrivée.
  ValueListenable<CibleLien?> get enAttente => _enAttente;

  /// À appeler une fois, dans `main()`. Sans effet hors Android.
  void demarrer() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _abonnement ??= AppLinks().uriLinkStream.listen(
      (uri) {
        final cible = analyserLienAlanya(uri.toString());
        if (cible != null) _enAttente.value = cible;
      },
      // Un lien illisible ne doit rien casser : il est simplement ignoré.
      onError: (Object _) {},
    );
  }

  /// Retire le lien en attente et le rend (nul s'il n'y en a pas).
  CibleLien? prendre() {
    final cible = _enAttente.value;
    _enAttente.value = null;
    return cible;
  }
}
