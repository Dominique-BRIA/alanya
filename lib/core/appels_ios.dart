import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'push_service.dart';

/// CE QUI N'EXISTE QUE SUR iPHONE POUR LES APPELS (19/11/2026).
///
/// Ne fait rien ailleurs : Android garde exactement son fonctionnement.
///
///  · LE JETON VoIP. Les appels entrants arrivent sur iPhone par PushKit, avec
///    un jeton à part de celui des notifications. Quand iOS le renouvelle, on
///    le réenregistre auprès du serveur.
///  · LE DÉCROCHÉ DEPUIS L'ÉCRAN VERROUILLÉ. L'application reste alors en
///    arrière-plan : Flutter ne produit plus d'images, si bien que l'arbre de
///    widgets — et l'écouteur d'appel qui rejoint la communication — peut ne
///    pas se construire avant que l'utilisateur ouvre l'application. Le natif
///    prévient (`decroche`), et l'on force quelques images le temps que
///    l'appel se branche.
class AppelsIos {
  AppelsIos._();

  static const _canal = MethodChannel('alanya/appels_ios');
  static bool _demarre = false;

  static void demarrer() {
    if (kIsWeb || !Platform.isIOS || _demarre) return;
    _demarre = true;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method == 'decroche') forcerImages();
      return null;
    });
    FlutterCallkitIncoming.onEvent.listen((evenement) {
      if (evenement is CallEventActionDidUpdateDevicePushTokenVoip) {
        unawaited(PushService.instance
            .registerTokenIfAuthenticated(depuisRenouvellement: true));
      }
      if (evenement is CallEventActionCallAccept) forcerImages();
    });
  }

  static Timer? _images;

  /// Quatre images par seconde pendant dix secondes.
  static void forcerImages() {
    _images?.cancel();
    var n = 0;
    _images = Timer.periodic(const Duration(milliseconds: 250), (t) {
      SchedulerBinding.instance.scheduleForcedFrame();
      if (++n >= 40) t.cancel();
    });
  }
}
