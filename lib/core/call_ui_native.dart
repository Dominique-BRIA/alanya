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
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Appel manqué',
        ),
        android: const AndroidParams(
          // Libellés des boutons : ils appartiennent à AndroidParams et non à
          // CallKitParams, l'écran étant rendu par la couche Android.
          textAccept: 'Répondre',
          textDecline: 'Refuser',
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

  /// Signale au système que l'appel est DÉCROCHÉ et en cours.
  ///
  /// ⚠️ SANS CET APPEL, le paquet reste bloqué sur « appel entrant ». Sa
  /// notification continue d'afficher Répondre / Refuser après que l'appel a
  /// commencé, son minuteur ne démarre pas, et raccrocher depuis l'application
  /// ne la fait pas disparaître : le paquet n'a jamais été informé que l'état
  /// avait changé. C'était l'origine commune de la plupart des incohérences
  /// entre la notification et l'écran d'appel.
  static Future<void> marquerConnecte(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (_) {}
  }

  /// Retire l'écran d'appel — appelant qui renonce, appel expiré, décroché
  /// depuis un autre appareil, ou raccroché depuis l'application.
  ///
  /// Termine AUSSI tout autre appel resté affiché : après un raccrochage, une
  /// notification orpheline continuerait d'égrener son minuteur pour un appel
  /// qui n'existe plus, et rien ne permettrait de la faire partir.
  static Future<void> masquer(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {
      // L'écran a pu être fermé par l'utilisateur entre-temps : il n'y a alors
      // rien à retirer, et l'échec n'a aucune conséquence.
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// Ferme tout écran d'appel encore affiché. Utile au démarrage : un appel
  /// resté affiché après un arrêt brutal sonnerait dans le vide.
  static Future<void> toutMasquer() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
