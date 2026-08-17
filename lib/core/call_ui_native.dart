import 'dart:io';

import 'package:alanya_telecom/alanya_telecom.dart';
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
    // Force le repli sur le paquet, sans retenter Telecom. Utilisé quand
    // Telecom a accepté la déclaration puis échoué à créer la `Connection` :
    // repasser par lui ne ferait qu'échouer une seconde fois.
    bool sansTelecom = false,
  }) async {
    // ── TELECOM D'ABORD, le paquet en repli ────────────────────────────────
    //
    // ⚠️ CE N'EST PAS UNE PRÉFÉRENCE D'ARCHITECTURE, C'EST LA CORRECTION D'UN
    // BUG MESURÉ. La sonnerie du paquet s'arrêtait au bout de 2,21 s,
    // application tuée (relevé sur TECNO KL5) : il démarre son son à
    // l'affichage de la notification, puis Telecom — qu'il sollicite pourtant
    // lui-même — réclame le focus audio de sonnerie et bascule la sortie sur
    // l'écouteur d'oreille. Deux acteurs pour un seul flux.
    //
    // Le module local démarre la sonnerie dans `onShowIncomingCallUi()`, le
    // rappel que Telecom déclenche APRÈS s'être installé, et que le paquet
    // n'implémente pas. Plus de course possible.
    //
    // Bénéfice qui décide de tout le reste : tant qu'une `Connection` vit,
    // Android LIE le processus et ne peut plus le geler. C'est la seule façon
    // de tenir une sonnerie sur Transsion ou Xiaomi, application tuée.
    if (Platform.isAndroid && !sansTelecom) {
      final prisEnCharge = await AlanyaTelecom.reportIncomingCall({
        // `callId` sert aussi de clé d'idempotence côté natif : le même appel
        // arrive par le socket ET par le push, et le module déduplique dessus.
        'callId': callId,
        'callerName': nom,
        // Le module compare à « audio » pour choisir son libellé. On lui parle
        // dans SA convention plutôt que de le modifier : il reste ainsi
        // identique à la version éprouvée, donc resynchronisable.
        'callType': video ? 'video' : 'audio',
        'callerAvatar': avatarUrl ?? '',
      });
      if (prisEnCharge) return;
    }

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
  /// Appels décrochés DEPUIS l'application, en attente de leur écho.
  ///
  /// ⚠️ INDISPENSABLE AVEC TELECOM. Le module émet un événement `answer` pour
  /// TOUT décrochage — y compris celui que nous venons de provoquer nous-mêmes
  /// en appelant `answerRinging`. Sans cette marque, l'écho repasserait par
  /// `_onCallAction('call_accept')`, qui rappellerait l'acceptation et
  /// ouvrirait un SECOND écran d'appel par-dessus le premier.
  static final Set<String> _decrochesDepuisApp = <String>{};

  /// Vrai si [callId] est l'écho d'un décrochage que nous avons provoqué —
  /// l'événement doit alors être ignoré. La marque est consommée au passage.
  static bool consommerEchoLocal(String? callId) =>
      callId != null && _decrochesDepuisApp.remove(callId);

  static Future<void> marquerConnecte(String callId) async {
    // Telecom doit savoir que l'appel est pris, sinon sa `Connection` reste en
    // sonnerie : la notification d'appel entrant resterait affichée pendant
    // toute la communication, et le filet de 90 s du module finirait par
    // raccrocher un appel en cours.
    //
    // Sans effet quand le décrochage vient déjà du natif : le module garde un
    // drapeau `accepted` et sort immédiatement.
    if (Platform.isAndroid) {
      _decrochesDepuisApp.add(callId);
      await AlanyaTelecom.answerRinging();
    }
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
    // Telecom en premier : une `Connection` laissée vivante continuerait de
    // sonner ET retiendrait le processus indéfiniment.
    if (Platform.isAndroid) {
      _decrochesDepuisApp.remove(callId);
      await AlanyaTelecom.endCall();
    }
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
    if (Platform.isAndroid) {
      _decrochesDepuisApp.clear();
      await AlanyaTelecom.endCall();
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// L'écran d'appel peut-il s'ouvrir par-dessus le verrouillage ?
  ///
  /// Renvoie vrai sous Android 14, où l'autorisation est acquise d'office, et
  /// sur les plateformes qui ignorent la question. Ne renvoie faux que dans le
  /// cas réellement problématique : Android 14 ou plus avec une autorisation
  /// refusée.
  static Future<bool> peutAfficherPleinEcran() async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterCallkitIncoming.canUseFullScreenIntent();
    } catch (_) {
      // Méthode absente sur une version plus ancienne du canal : on suppose que
      // c'est bon plutôt que d'alarmer sans raison.
      return true;
    }
  }

  /// Ouvre la page système où l'utilisateur accorde l'autorisation.
  ///
  /// Android n'offre AUCUNE boîte de dialogue pour celle-ci, contrairement aux
  /// notifications : la seule voie possible est de renvoyer vers les réglages.
  /// C'est pourquoi elle est présentée dans une explication maison — sans quoi
  /// l'utilisateur atterrirait sur une page système sans savoir pourquoi.
  static Future<void> demanderPleinEcran() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }
}
