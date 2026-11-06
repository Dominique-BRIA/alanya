import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../l10n/app_localizations.dart';
import 'appel_natif_prefs.dart';
import 'push_service.dart';
import 'token_storage.dart';

/// L'écran d'appel entrant NATIF — CallKit, comme l'application de référence
/// (06/11/2026).
///
/// Sur Android, application fermée ou en arrière-plan, c'est l'écran plein de
/// `flutter_callkit_incoming`, redessiné à nos couleurs
/// (`res/layout/callkit_incoming_content.xml`). Il est affiché par le NATIF
/// (`CallIncomingHelper.kt`) : depuis le push sans démarrer Flutter, ou depuis
/// ici quand l'appel arrive par le socket application en arrière-plan. Un seul
/// chemin d'affichage, donc une seule série de gardes : doublon, appel déjà
/// terminé, communication en cours, sonnerie.
///
/// Le refus, le décroché et la fin sont suivis par le natif
/// (`AlanyaApplication.kt`, écouteur ACTIVE_CALLS). Tout retrait décidé ICI est
/// donc signalé « programmatique » au natif AVANT d'être fait : sinon il le
/// prendrait pour un refus de l'utilisateur et refuserait l'appel au serveur.
class CallUiNative {
  CallUiNative._();

  static const _natif = MethodChannel('com.alanya/call_native');

  /// Libellé traduit quand l'interface existe, repli français sinon.
  static String _libelle(String cle, String repliFrancais) {
    final ctx = PushService.navigatorKey.currentContext;
    if (ctx == null) return repliFrancais;
    try {
      return tr(ctx, cle);
    } catch (_) {
      return repliFrancais;
    }
  }

  /// Affiche l'appel entrant.
  ///
  /// [callId] doit être l'identifiant serveur de l'appel : c'est lui qui
  /// permettra de fermer l'écran quand l'appelant raccroche, et de savoir quel
  /// appel accepter quand l'utilisateur décroche. [appelant] porte le reste de
  /// l'identité, sous les noms du push (`callerId`, `convId`, `isGroup`,
  /// `groupName`).
  static Future<void> afficherAppelEntrant({
    required String callId,
    required String nom,
    String? avatarUrl,
    bool video = false,
    Map<String, String> appelant = const {},
  }) async {
    // Appel déjà terminé (annulation arrivée AVANT lui) : rien ne sonne.
    if (await AppelsTermines.contient(callId)) return;

    if (Platform.isAndroid) {
      // Le natif charge la photo et envoie un éventuel refus sans Flutter :
      // il lui faut le jeton d'accès à jour (voir PontNatifAppel).
      await PontNatifAppel.publierJeton(await TokenStorage().accessToken);
      try {
        await _natif.invokeMethod<void>('showIncoming', {
          ...appelant,
          'callId': callId,
          'callerName': nom,
          'callerAvatarUrl': avatarUrl ?? '',
          'callType': video ? 'VIDEO' : 'AUDIO',
        });
        return;
      } on MissingPluginException {
        // Isolate sans le canal de l'activité : le paquet, en direct.
      }
    }

    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: callId,
        nameCaller: nom,
        appName: 'Alanya Work',
        avatar: avatarUrl,
        handle: appelant['callerId'],
        type: video ? 1 : 0,
        duration: 60000,
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: _libelle('missed_call', 'Appel manqué'),
        ),
        // Android : ne PAS démarrer le service de premier plan au tap
        // « Accepter » — il ne peut pas honorer startForeground() si le moteur
        // Flutter n'est pas encore attaché. Même contrat que le chemin natif.
        callingNotification: const NotificationParams(showNotification: false),
        extra: {
          ...appelant,
          'callId': callId,
          'callerName': nom,
          'callerPhoto': avatarUrl ?? '',
          'isVideo': video,
          'shownAt': DateTime.now().millisecondsSinceEpoch,
        },
        android: AndroidParams(
          textAccept: _libelle('accept', 'Accepter'),
          textDecline: _libelle('decline', 'Refuser'),
          isCustomNotification: true,
          isShowLogo: false,
          isShowFullLockedScreen: true,
          backgroundColor: '#00000000',
          actionColor: '#2D6A4F',
          textColor: '#FFFFFFFF',
          incomingCallNotificationChannelName:
              _libelle('incoming_calls', 'Appels entrants'),
          missedCallNotificationChannelName:
              _libelle('missed_calls', 'Appels manqués'),
        ),
        ios: const IOSParams(supportsVideo: true),
      ),
    );
  }

  /// Signale au système que l'appel est DÉCROCHÉ et en cours.
  ///
  /// ⚠️ SANS CET APPEL, le paquet reste bloqué sur « appel entrant » : sa
  /// notification continue d'afficher Accepter / Refuser après que l'appel a
  /// commencé.
  static Future<void> marquerConnecte(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[CallUiNative] setCallConnected : $e');
    }
  }

  /// Prévient le natif que ces retraits viennent de l'application (fin
  /// d'appel, nettoyage, reprise par l'écran Flutter) et non d'un refus de
  /// l'utilisateur. Sans ce marquage, l'écouteur ACTIVE_CALLS prend tout
  /// retrait non accepté pour un refus — et refuse au serveur un appel qui
  /// sonne peut-être encore ailleurs.
  static Future<void> _marquerRetraitProgrammatique(List<String> ids) async {
    if (!Platform.isAndroid) return;
    final liste = ids.where((id) => id.trim().isNotEmpty).toList();
    if (liste.isEmpty) return;
    try {
      await _natif.invokeMethod<void>(
          'markProgrammaticDismiss', {'callIds': liste});
    } catch (e) {
      debugPrint('[CallUiNative] markProgrammaticDismiss : $e');
    }
  }

  /// Retire l'écran d'appel de [callId] — et lui seul : appelant qui
  /// renonce, appel expiré, décroché ailleurs, ou raccroché depuis
  /// l'application. L'appel est noté terminé.
  static Future<void> masquer(String callId) async {
    final id = callId.trim();
    if (id.isEmpty) return;
    await AppelsTermines.marquer(id);
    await _marquerRetraitProgrammatique([id]);
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {
      // Déjà retiré entre-temps : rien à faire.
    }
  }

  /// Retire l'écran natif SANS terminer l'appel : l'écran Flutter reprend la
  /// sonnerie (application revenue au premier plan pendant qu'elle sonnait).
  static Future<void> masquerSilencieusement(String callId) async {
    final id = callId.trim();
    if (id.isEmpty) return;
    await _marquerRetraitProgrammatique([id]);
    if (Platform.isAndroid) {
      try {
        await _natif.invokeMethod<void>('dismissIncomingSilently', {'callId': id});
      } catch (e) {
        debugPrint('[CallUiNative] dismissIncomingSilently : $e');
      }
    }
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }

  /// Ferme tout écran d'appel encore affiché (nettoyage), sans qu'aucun
  /// retrait soit pris pour un refus.
  static Future<void> toutMasquer() async {
    final ids = <String>[];
    try {
      for (final c in await FlutterCallkitIncoming.activeCalls()) {
        if (c.id.trim().isNotEmpty) ids.add(c.id.trim());
      }
    } catch (_) {}
    await _marquerRetraitProgrammatique(ids);
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// Âge maximal d'une entrée non acceptée pour être reprise au démarrage :
  /// au-delà de la sonnerie (60 s) et d'une marge, c'est un débris.
  static const _ageMaxNonAccepte = Duration(seconds: 90);

  /// Âge maximal d'une entrée acceptée : passé ce délai, le processus est
  /// mort en plein appel, et reprendre l'acceptation produirait un appel
  /// fantôme.
  static const _ageMaxAccepte = Duration(minutes: 3);

  /// L'appel CallKit le plus récent ET plausible, ou `null` — comme
  /// `getActiveCall` dans l'application de référence. Sert au démarrage à
  /// froid et au retour au premier plan :
  /// - `isAccepted` vrai → « Accepter » a été touché avant Flutter ;
  /// - `isAccepted` faux → l'appel sonne encore sur l'écran natif.
  static Future<Map<String, dynamic>?> appelActif() async {
    try {
      final appels = await FlutterCallkitIncoming.activeCalls();
      if (appels.isEmpty) return null;
      CallKitParams? meilleur;
      var meilleurShownAt = -1;
      final maintenant = DateTime.now().millisecondsSinceEpoch;
      for (final c in appels) {
        final extra = c.extra ?? const {};
        final shownAt = int.tryParse('${extra['shownAt'] ?? ''}') ?? 0;
        if (shownAt > 0) {
          final age = maintenant - shownAt;
          final ageMax = c.isAccepted
              ? _ageMaxAccepte.inMilliseconds
              : _ageMaxNonAccepte.inMilliseconds;
          if (age > ageMax) continue;
        }
        if (meilleur == null || shownAt > meilleurShownAt) {
          meilleur = c;
          meilleurShownAt = shownAt;
        }
      }
      if (meilleur == null) return null;
      final extra = meilleur.extra ?? const {};
      return {
        'callId': (extra['callId'] ?? meilleur.id).toString(),
        'callerId': (extra['callerId'] ?? meilleur.handle ?? '').toString(),
        'callerName': (extra['callerName'] ?? meilleur.nameCaller ?? '').toString(),
        'callerPhoto': extra['callerPhoto']?.toString(),
        'isVideo': extra['isVideo'] == true || extra['isVideo'] == 'true',
        'convId': extra['convId']?.toString(),
        'isGroup': extra['isGroup'] == true || extra['isGroup'] == 'true',
        'groupName': extra['groupName']?.toString(),
        'isAccepted': meilleur.isAccepted,
      };
    } catch (e) {
      debugPrint('[CallUiNative] activeCalls : $e');
    }
    return null;
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
      return true;
    }
  }

  /// Ouvre la page système où l'utilisateur accorde l'autorisation.
  ///
  /// Android n'offre AUCUNE boîte de dialogue pour celle-ci, contrairement aux
  /// notifications : la seule voie possible est de renvoyer vers les réglages.
  static Future<void> demanderPleinEcran() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }
}
