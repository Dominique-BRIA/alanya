import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'geo_service.dart';
import 'token_storage.dart';

/// Relevé de position quand l'application est fermée.
///
/// ## Pourquoi un service de premier plan, et pas autre chose
///
/// `workmanager` ne descend pas sous **quinze minutes** d'intervalle : les cinq
/// minutes demandées ne peuvent passer que par un service de premier plan, donc
/// par une **notification permanente**. Ce n'est pas un choix d'implémentation,
/// c'est une contrainte d'Android : aucune application ne relève une position
/// toutes les cinq minutes en arrière-plan sans se montrer.
///
/// ## Ce que fait l'isolat, et ce qu'il ne fait PAS
///
/// Il relève, met en file, et tente d'envoyer avec le jeton d'accès en place.
///
/// ⚠️ **IL NE RAFRAÎCHIT JAMAIS LES JETONS**, et c'est délibéré. Le verrou de
/// rafraîchissement d'`AuthedApi` est un `static` : il ne protège qu'à
/// l'intérieur d'un isolat. Or `rotateRefreshToken` révoque l'ancien jeton
/// immédiatement côté serveur — deux isolats qui rafraîchiraient en même temps
/// déconnecteraient l'un des deux. Le prix de cette prudence : quand
/// l'application reste fermée plus d'un quart d'heure, les relevés s'accumulent
/// au lieu de partir. **Ils ne sont pas perdus** — `collectedAt` porte l'heure
/// du relevé, pas celle de l'envoi, donc la trace reste juste quelle que soit sa
/// date d'arrivée.
///
/// ## Le piège des préférences partagées entre isolats
///
/// `SharedPreferences` met ses valeurs en cache PAR ISOLAT. Ce que celui-ci
/// écrit reste invisible de l'application tant qu'elle n'appelle pas `reload()`
/// — voir `GeoService.viderLaFile`, qui le fait avant toute lecture. Sans cela,
/// l'application viderait une file qu'elle croit vide et écraserait les relevés
/// de l'arrière-plan.
///
/// ## La limite qu'aucune bibliothèque ne corrige
///
/// Plusieurs constructeurs — Xiaomi, Huawei, Oppo, Samsung à un moindre degré —
/// tuent les services de premier plan des applications non exemptées
/// d'optimisation de batterie. La collecte application fermée n'est donc jamais
/// garantie à 100 % sur tout le parc, quelle que soit l'implémentation.

/// Point d'entrée de l'isolat.
///
/// ⚠️ `@pragma('vm:entry-point')` est OBLIGATOIRE : sans lui, la compilation en
/// mode release retire cette fonction — elle n'est appelée par aucun code Dart —
/// et le service démarre sur un vide, sans la moindre erreur.
@pragma('vm:entry-point')
void pointEntreeTacheGeo() {
  FlutterForegroundTask.setTaskHandler(_TacheGeo());
}

class _TacheGeo extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Les greffons ne sont pas enregistrés d'office dans un isolat secondaire :
    // sans cet appel, le premier accès à la position ou au stockage sécurisé
    // échoue sur un canal de plateforme absent.
    DartPluginRegistrant.ensureInitialized();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Volontairement sans attente : la signature est synchrone, et une exception
    // qui remonterait d'ici tuerait le service.
    _releveEtEnvoie().catchError((Object e) {
      debugPrint('[GeoBackground] relevé impossible : $e');
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  Future<void> _releveEtEnvoie() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 45),
      ),
    );

    final releve = jsonEncode({
      'lat': position.latitude,
      'lon': position.longitude,
      'collectedAt': position.timestamp.toUtc().toIso8601String(),
    });

    // On écrit AVANT de tenter l'envoi : si l'envoi échoue, ou si le service est
    // tué au milieu, le relevé est déjà à l'abri.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final file = prefs.getStringList(GeoService.cleFile) ?? <String>[];
    file.add(releve);
    while (file.length > GeoService.tailleMaxFile) {
      file.removeAt(0);
    }
    await prefs.setStringList(GeoService.cleFile, file);

    // Envoi au jeton d'accès EN PLACE, sans jamais le rafraîchir. Un échec
    // laisse simplement la file grandir ; l'application la videra.
    final token = await TokenStorage().accessToken;
    if (token == null) return;
    try {
      await ApiClient().post(
          '/api/geo', jsonDecode(releve) as Map<String, dynamic>,
          bearer: token);
      final restant = (prefs.getStringList(GeoService.cleFile) ?? <String>[])
        ..remove(releve);
      await prefs.setStringList(GeoService.cleFile, restant);
    } catch (e) {
      debugPrint('[GeoBackground] envoi différé : $e');
    }
  }
}
