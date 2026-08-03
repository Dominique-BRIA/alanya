import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Écran d'appel entrant NATIF, façon téléphone.
///
/// Remplace la notification locale pour les appels entrants. La différence est
/// visible : au lieu d'un bandeau de texte, Android affiche un vrai écran
/// d'appel — avatar, nom, deux gros boutons — et le pose PAR-DESSUS l'écran
/// verrouillé, application tuée comprise.
///
/// POURQUOI UN PAQUET PLUTÔT QUE DU KOTTLIN. Cette apparence vient de
/// `Notification.CallStyle` (Android 12+), que `flutter_local_notifications`
/// n'expose pas. L'écrire à la main aurait demandé de reconstruire la
/// notification en natif ET de la déclencher depuis l'isolate d'arrière-plan de
/// Firebase, où les canaux d'activité ne sont pas disponibles. Le paquet règle
/// exactement ce point, sur les deux plateformes.
class CallUiNative {
  CallUiNative._();

  /// Affiche l'appel entrant.
  ///
  /// [callId] doit être l'identifiant serveur de l'appel : c'est lui qui
  /// permettra de fermer l'écran quand l'appelant raccroche, et de savoir quel
  /// appel accepter quand l'utilisateur décroche.
  static Future<void> afficherAppelEntrant({
    required String callId,
    required String nom,
    String? avatarUrl,
    bool video = false,
  }) async {
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: callId,
        nameCaller: nom,
        appName: 'Alanya Work',
        avatar: avatarUrl,
        type: video ? 1 : 0,
        // Durée de sonnerie alignée sur celle de l'appelant, qui raccroche à
        // 60 s : un écran qui sonnerait plus longtemps afficherait un appel que
        // plus personne ne passe.
        duration: 60000,
        textAccept: 'Répondre',
        textDecline: 'Refuser',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Appel manqué',
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          // Les deux réglages qui font tout le comportement recherché :
          // l'écran occupe tout l'affichage et passe par-dessus le verrouillage.
          isShowFullLockedScreen: true,
          isImportant: true,
          isBot: false,
          // Terre cuite d'Alanya, pour que l'écran natif reste dans l'identité.
          backgroundColor: '#B85C38',
          actionColor: '#2D6A4F',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Appels entrants',
          missedCallNotificationChannelName: 'Appels manqués',
        ),
        ios: const IOSParams(supportsVideo: true),
      ),
    );
  }

  /// Retire l'écran d'appel — appelant qui renonce, appel expiré, ou décroché
  /// depuis un autre appareil.
  static Future<void> masquer(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {
      // L'écran a pu être fermé par l'utilisateur entre-temps : il n'y a alors
      // rien à retirer, et l'échec n'a aucune conséquence.
    }
  }

  /// Ferme tout écran d'appel encore affiché. Utile au démarrage : un appel
  /// resté affiché après un arrêt brutal sonnerait dans le vide.
  static Future<void> toutMasquer() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
