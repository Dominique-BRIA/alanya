import 'package:flutter/services.dart';

/// Pont vers le module natif Telecom (ConnectionService self-managed,
/// Android 8+). Tant qu'un appel est déclaré (sonnerie OU communication),
/// Android LIE le processus de l'app → la sonnerie joue toujours, même app
/// en arrière-plan gelée ou tuée.
///
/// Tous les appels sont sûrs : en cas d'échec natif (vieil Android, compte
/// Telecom refusé par l'OEM), `reportIncomingCall` renvoie false et
/// l'appelant doit utiliser le fallback (flutter_callkit_incoming).
class AlanyaTelecom {
  static const MethodChannel _ch = MethodChannel('alanya_telecom');
  static void Function(String event, Map<String, dynamic> data)? _listener;
  static bool _handlerSet = false;

  /// Événements natifs : 'answer' | 'reject' | 'timeout' | 'telecom_failed'
  /// | 'reopen' (appui sur le chip vert de la barre d'état : REVENIR à un
  /// appel déjà décroché, sans rien accepter — charge vide, l'appel courant
  /// est celui que connaît déjà l'application).
  /// data = le map passé à reportIncomingCall (callerName, callerPhone,
  /// roomId, callType, groupAdd, callerAvatar…).
  static void setListener(
      void Function(String event, Map<String, dynamic> data)? l) {
    _listener = l;
    if (!_handlerSet) {
      _handlerSet = true;
      _ch.setMethodCallHandler((call) async {
        final data = (call.arguments is Map)
            ? Map<String, dynamic>.from(call.arguments as Map)
            : <String, dynamic>{};
        _listener?.call(call.method, data);
      });
    }
  }

  /// Configure l'URL de base de l'API (HTTPS obligatoire) pour le refus
  /// HTTP natif. À appeler au démarrage de chaque isolate (main + FCM BG).
  /// SÉCURITÉ : l'URL n'est jamais lue du payload d'appel.
  static Future<void> configure({required String apiUrl}) async {
    try {
      await _ch.invokeMethod('configure', {'apiUrl': apiUrl});
    } catch (_) {}
  }

  /// Déclare l'appel entrant au système (sonne nativement).
  /// false → utiliser le fallback notification classique.
  static Future<bool> reportIncomingCall(Map<String, String> data) async {
    try {
      return await _ch.invokeMethod<bool>('reportIncomingCall', data) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Termine l'appel Telecom courant (annulation appelant, fin de
  /// communication, nettoyage). [missed] = clôture « appel manqué ».
  static Future<void> endCall({bool missed = false}) async {
    try {
      await _ch.invokeMethod('endCall', {'missed': missed});
    } catch (_) {}
  }

  /// Coupe la sonnerie native (ex. : l'écran d'appel entrant Flutter prend
  /// le relais avec sa propre sonnerie).
  static Future<void> silenceRinger() async {
    try {
      await _ch.invokeMethod('silenceRinger');
    } catch (_) {}
  }

  /// Force la route audio via l'API Android Telecom
  static Future<void> setSpeaker(bool speakerOn) async {
    try {
      await _ch.invokeMethod('setSpeaker', {'speakerOn': speakerOn});
    } catch (_) {}
  }

  /// Pose le chip vert « appel en cours » dans la barre d'état (Android 12+).
  ///
  /// À appeler quand l'appel est ÉTABLI. Sans effet en dessous d'Android 12,
  /// où le style d'appel n'existe pas.
  ///
  /// POURQUOI DEPUIS DART. Le chip était accroché au décroché natif de Telecom,
  /// qui ne connaît qu'un seul cas : un appel entrant reçu application en
  /// arrière-plan. Application déjà ouverte, l'appel n'est jamais déclaré au
  /// système ; un appel sortant non plus. Dans ces deux cas il n'existe aucune
  /// `Connection`, donc aucun chip. Dart, lui, sait toujours qu'un appel tourne.
  ///
  /// Idempotent : un second appel pour la MÊME communication rafraîchit la
  /// notification sans remettre le chronomètre à zéro.
  static Future<void> chipDemarrer({required String nom}) async {
    try {
      await _ch.invokeMethod('chipDemarrer', {'nom': nom});
    } catch (_) {}
  }

  /// Retire le chip. Idempotent : sans effet si aucun n'est posé.
  static Future<void> chipArreter() async {
    try {
      await _ch.invokeMethod('chipArreter');
    } catch (_) {}
  }

  /// Décroche l'appel qui sonne (équivalent au bouton de la notification).
  static Future<void> answerRinging() async {
    try {
      await _ch.invokeMethod('answerRinging');
    } catch (_) {}
  }

  /// Refuse l'appel qui sonne.
  static Future<void> rejectRinging() async {
    try {
      await _ch.invokeMethod('rejectRinging');
    } catch (_) {}
  }

  /// Appel en train de SONNER (démarrage à froid via full-screen intent) —
  /// null si aucun.
  static Future<Map<String, dynamic>?> getRingingCall() async {
    try {
      final r = await _ch.invokeMethod('getRingingCall');
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  /// Appel DÉJÀ DÉCROCHÉ via la notification (démarrage à froid) — null si
  /// aucun. Sert à naviguer directement vers l'écran d'appel.
  static Future<Map<String, dynamic>?> getAcceptedCall() async {
    try {
      final r = await _ch.invokeMethod('getAcceptedCall');
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }
}
