import 'dart:io';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un appel qui arrive PENDANT une communication (06/11/2026).
///
/// Il s'affichait comme n'importe quel appel : plein écran par-dessus la
/// conversation en cours, sonnerie comprise. Le serveur ne l'empêche pas — un
/// appel de groupe sonne chez tout le monde, occupé ou non. Il s'affiche donc
/// désormais en SOURDINE, dans le tiroir de notifications : l'information
/// reste, l'intrusion part. Même règle que l'application de référence.
///
/// 🔴 L'ARRIÈRE-PLAN DOIT POUVOIR LE SAVOIR. Écran éteint en pleine
/// communication, l'application n'est plus au premier plan : c'est le push,
/// traité dans un isolate à part qui ne partage AUCUNE mémoire avec
/// l'application, qui déclarait l'appel au système. D'où cette marque dans les
/// préférences, que les deux isolates lisent.
///
/// ⚠️ LA MARQUE PORTE LE NUMÉRO DU PROCESSUS. Si Android tue l'application en
/// pleine communication, personne n'efface la marque — et tous les appels
/// suivants arriveraient en sourdine, sans que rien ne l'explique. Or une
/// communication ne survit pas à son processus : une marque posée par un autre
/// processus que celui qui la lit est forcément périmée.
class CommunicationEnCours {
  CommunicationEnCours._();

  static const _cle = 'communication_en_cours_pid';

  /// Posée par `CallForegroundService` au début de tout appel ou réunion
  /// actif, retirée à sa fin.
  static Future<void> marquer(bool active) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (active) {
        await p.setString(_cle, '$pid');
      } else {
        await p.remove(_cle);
      }
    } catch (_) {
      // Préférences indisponibles : au pire, un appel sonnera normalement
      // pendant une communication — le comportement d'avant.
    }
  }

  /// Une communication est-elle en cours dans CE processus ?
  ///
  /// Lisible depuis l'isolate du push : `reload()` relit le disque, l'isolate
  /// pouvant garder une copie ancienne d'un message à l'autre.
  static Future<bool> estEnCours() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      if (p.getString(_cle) == '$pid') return true;
    } catch (_) {}
    // Un appel décroché depuis l'écran natif est en cours côté CallKit avant
    // même que l'application n'ait démarré son service.
    try {
      final appels = await FlutterCallkitIncoming.activeCalls();
      if (appels.any((c) => c.isAccepted)) return true;
    } catch (_) {}
    return false;
  }

  /// Canal SILENCIEUX : pas de son, pas de vibration, pas de bandeau qui
  /// descend par-dessus l'appel en cours — seulement une ligne dans le tiroir.
  static const canal = AndroidNotificationChannel(
    'calls_pendant_communication',
    'Appels pendant une communication',
    description: 'Appels reçus alors que vous étiez déjà en communication',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  /// Identifiant distinct de celui de l'appel entrant : l'annulation de
  /// l'appel par l'appelant ne doit pas effacer la trace qu'il a appelé.
  static int idNotification(String? callId) =>
      ((callId ?? '').hashCode ^ 0x5a5a5a) & 0x7fffffff;

  /// Affiche la ligne discrète « X vous appelle ». [plugin] doit être
  /// initialisé dans l'isolate appelant.
  static Future<void> afficher(
    FlutterLocalNotificationsPlugin plugin, {
    required String? callId,
    required String nom,
    required String texte,
  }) async {
    try {
      if (Platform.isAndroid) {
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(canal);
      }
      await plugin.show(
        idNotification(callId),
        nom,
        texte,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canal.id,
            canal.name,
            channelDescription: canal.description,
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.missedCall,
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentSound: false,
            presentBanner: false,
            presentList: true,
          ),
        ),
      );
    } catch (_) {}
  }
}
