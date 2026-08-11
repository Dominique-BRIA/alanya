import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'authed_api.dart';
import 'geo_background.dart';
import 'push_service.dart';

/// Décision de l'utilisateur sur le suivi de position.
///
/// Trois états et non un booléen : « pas encore demandé » n'est pas « refusé ».
/// Sans cette distinction, on redemanderait à chaque lancement à quelqu'un qui a
/// dit non — ce que la règle du Play Store interdit, et qui est de toute façon
/// hostile.
enum ConsentementGeo { jamaisDemande, accepte, refuse }

/// Relevé de position des agents.
///
/// ## Ce que la table impose
///
/// **UNE LIGNE = UN LIEU, PAS UN RELEVÉ.** Le téléphone relève sa position à
/// intervalle régulier, mais le SERVEUR décide s'il s'agit d'un nouvel endroit
/// ou de la prolongation du précédent — c'est lui qui détient la dernière
/// position connue, et la règle (un rayon de 50 m) reste ainsi modifiable sans
/// reconstruire l'application. Le téléphone se contente d'envoyer ce qu'il lit.
///
/// ## Ce que la loi et le Play Store imposent
///
/// L'application part en distribution PUBLIQUE. `ACCESS_BACKGROUND_LOCATION`
/// exige donc un écran de divulgation DANS l'application **avant** toute demande
/// de permission, un vrai choix, et une politique de confidentialité publique.
/// Un refus ne bloque RIEN : la localisation n'est pas l'usage principal d'une
/// messagerie, et l'exiger serait un motif de rejet autant qu'une brutalité.
///
/// ## Qui est suivi
///
/// Le serveur seul en décide (`/api/me` → `suiviPosition`), et seuls les comptes
/// rattachés à une entreprise le sont. Pour un particulier, rien de tout ceci ne
/// se déclenche : ni écran, ni permission, ni relevé.
class GeoService {
  GeoService._();
  static final GeoService instance = GeoService._();

  AuthedApi? _api;

  static const _cleConsentement = 'geo_consentement';

  /// ⚠️ PUBLIQUES parce que l'ISOLAT D'ARRIÈRE-PLAN écrit dans la même file.
  /// Deux constantes séparées auraient fini par diverger, et l'application
  /// viderait alors une file que le service remplit ailleurs.
  static const cleFile = 'geo_file_attente';

  /// Plafond de la file hors ligne.
  ///
  /// À un relevé toutes les cinq minutes, 288 couvrent une journée entière sans
  /// réseau. Au-delà, on jette les PLUS ANCIENS : une trace récente vaut mieux
  /// qu'une trace complète mais périmée, et une file sans limite finirait par
  /// remplir les préférences.
  static const tailleMaxFile = 288;

  Timer? _minuteur;
  bool _envoiEnCours = false;

  void init(AuthedApi api) => _api = api;

  // ── Consentement ─────────────────────────────────────────────────────────

  Future<ConsentementGeo> consentement() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_cleConsentement)) {
      case 'accepte':
        return ConsentementGeo.accepte;
      case 'refuse':
        return ConsentementGeo.refuse;
      default:
        return ConsentementGeo.jamaisDemande;
    }
  }

  Future<void> enregistreConsentement(bool accepte) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleConsentement, accepte ? 'accepte' : 'refuse');
  }

  // ── Permissions ──────────────────────────────────────────────────────────

  /// Demande la localisation, dans l'ordre qu'Android impose.
  ///
  /// ⚠️ EN DEUX TEMPS, ET PAS AUTREMENT. « Pendant l'utilisation » d'abord ;
  /// « toujours autoriser » ensuite, et seulement une fois la première obtenue.
  /// Demander les deux d'un bloc fait échouer la seconde **en silence** : le
  /// système la refuse sans rien afficher, et l'application croit l'avoir.
  ///
  /// Renvoie `true` dès que la position « pendant l'utilisation » est acquise :
  /// c'est assez pour relever tant que l'application vit. Le suivi application
  /// fermée demandera en plus « toujours », mais son absence ne doit pas tout
  /// annuler — mieux vaut une trace partielle que pas de trace.
  Future<bool> demandePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // Second temps. `whileInUse` signifie que « toujours » n'a pas été accordé :
    // sur Android récent, il ne s'obtient que dans les réglages du système, et
    // cet appel y conduit. Son échec n'est PAS bloquant.
    if (permission == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
    }
    return true;
  }

  // ── Collecte ─────────────────────────────────────────────────────────────

  /// Ouvre les réglages de localisation du système.
  ///
  /// Le seul chemin possible quand le GPS est coupé : aucune boîte de dialogue
  /// ne permet de le rallumer à la place de l'utilisateur.
  Future<void> ouvrirReglagesLocalisation() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }

  /// Démarre le relevé si, et seulement si, tout est réuni.
  ///
  /// Idempotent : appelable à chaque retour au premier plan sans rien empiler.
  Future<void> demarrer({required int intervalleMin}) async {
    if (_minuteur != null) return;
    if (await consentement() != ConsentementGeo.accepte) return;
    if (!await demandePermissions()) {
      /*
       * ⚠️ RAPPEL SEULEMENT SI L'UTILISATEUR AVAIT ACCEPTÉ — la garde du dessus
       * s'en assure, et l'ordre des deux conditions n'est pas indifférent.
       *
       * Quelqu'un qui a REFUSÉ le suivi ne doit jamais être relancé : la règle
       * du Play Store l'interdit, et harceler quelqu'un qui a dit non ne le fera
       * pas changer d'avis. Ce rappel ne s'adresse qu'à celui qui a dit oui puis
       * coupé sa localisation — pour lui, c'est un service rendu, il croit être
       * suivi et ne l'est plus.
       */
      await PushService.instance.showRappelLocalisation();
      return;
    }

    final periode = Duration(minutes: intervalleMin > 0 ? intervalleMin : 5);
    // Un premier relevé tout de suite : attendre cinq minutes pour savoir où se
    // trouve quelqu'un qui vient d'ouvrir l'application n'aurait aucun sens.
    unawaited(_releve());
    _minuteur = Timer.periodic(periode, (_) => unawaited(_releve()));
    await _demarreServicePremierPlan(periode);
    debugPrint('[GeoService] relevé démarré (${periode.inMinutes} min)');
  }

  /// Arrête le relevé. À appeler à la déconnexion — sans quoi le téléphone
  /// continuerait de rapporter la position d'un compte qui n'est plus là.
  Future<void> arreter() async {
    _minuteur?.cancel();
    _minuteur = null;
    if (Platform.isAndroid) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    }
  }

  /// Démarre le service qui fait survivre le relevé à la fermeture.
  ///
  /// ⚠️ LA NOTIFICATION PERMANENTE EST INÉVITABLE, pas un choix. `workmanager`
  /// ne descend pas sous quinze minutes d'intervalle : les cinq minutes
  /// demandées ne peuvent passer que par un service de premier plan, et Android
  /// impose qu'un tel service se montre.
  ///
  /// Le minuteur du dessus reste en place : il couvre l'application vivante,
  /// tandis que le service couvre l'application fermée. Un relevé de trop, très
  /// occasionnellement, vaut mieux qu'un trou pendant la bascule — et le serveur
  /// le traitera de toute façon comme une prolongation, pas comme un lieu de
  /// plus.
  Future<void> _demarreServicePremierPlan(Duration periode) async {
    if (!Platform.isAndroid) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'alanya_localisation',
          channelName: 'Localisation',
          channelDescription:
              "Indique que votre position est relevée pour votre entreprise.",
          // La notification ne doit pas vibrer ni sonner toutes les cinq
          // minutes : elle informe, elle n'alerte pas.
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(periode.inMilliseconds),
          // Reprend après un redémarrage du téléphone : sans cela, la collecte
          // s'arrêterait la nuit et ne repartirait qu'à la prochaine ouverture.
          autoRunOnBoot: true,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      await FlutterForegroundTask.startService(
        notificationTitle: "Alanya Work — localisation active",
        notificationText:
            "Votre position est relevée toutes les ${periode.inMinutes} minutes.",
        callback: pointEntreeTacheGeo,
      );
    } catch (e) {
      // Service refusé par le système (permission manquante, constructeur
      // restrictif) : le relevé continue tant que l'application vit. Mieux vaut
      // une trace partielle que pas de trace du tout.
      debugPrint('[GeoService] service de premier plan indisponible : $e');
    }
  }

  Future<void> _releve() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Sans plafond, un GPS qui ne accroche pas laisserait la lecture
          // pendante jusqu'au relevé suivant, et deux lectures se
          // chevaucheraient.
          timeLimit: Duration(seconds: 45),
        ),
      );
      await _envoieOuMetEnFile({
        'lat': position.latitude,
        'lon': position.longitude,
        // L'heure du RELEVÉ, pas de l'envoi : c'est ce qui rend la trace juste
        // même quand la file a attendu le retour du réseau.
        'collectedAt': position.timestamp.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[GeoService] relevé impossible : $e');
    }
  }

  // ── Envoi et file hors ligne ─────────────────────────────────────────────

  Future<void> _envoieOuMetEnFile(Map<String, dynamic> releve) async {
    await _ajouteALaFile(releve);
    await viderLaFile();
  }

  Future<void> _ajouteALaFile(Map<String, dynamic> releve) async {
    final prefs = await SharedPreferences.getInstance();
    final file = prefs.getStringList(cleFile) ?? <String>[];
    file.add(jsonEncode(releve));
    // On jette par le DÉBUT : les relevés les plus anciens sont ceux dont
    // l'absence se remarque le moins.
    while (file.length > tailleMaxFile) {
      file.removeAt(0);
    }
    await prefs.setStringList(cleFile, file);
  }

  /// Envoie ce qui attend, dans l'ordre. À appeler aussi au retour du réseau.
  ///
  /// ⚠️ Un seul envoi à la fois : deux vidages concurrents enverraient les mêmes
  /// relevés en double, et le serveur ne peut pas les distinguer — deux lectures
  /// au même endroit sont légitimement identiques.
  Future<void> viderLaFile() async {
    final api = _api;
    if (api == null || _envoiEnCours) return;
    _envoiEnCours = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // ⚠️ `reload()` OBLIGATOIRE. `SharedPreferences` met ses valeurs en cache
      // PAR ISOLAT : ce que le service d'arrière-plan a écrit reste invisible
      // ici tant qu'on ne relit pas le disque. Sans cet appel, l'application
      // viderait une file qu'elle croit vide, puis l'écraserait — et tous les
      // relevés faits application fermée disparaîtraient.
      await prefs.reload();
      var file = prefs.getStringList(cleFile) ?? <String>[];

      while (file.isNotEmpty) {
        final brut = file.first;
        try {
          await api.post('/api/geo', jsonDecode(brut) as Map<String, dynamic>);
        } on ApiException catch (e) {
          // 422 = relevé refusé (trop ancien, coordonnées invalides). Le
          // réessayer indéfiniment bloquerait toute la file derrière lui : on
          // l'abandonne, c'est le seul cas où un relevé est perdu volontairement.
          if (e.statusCode != 422) rethrow;
          debugPrint('[GeoService] relevé refusé (${e.statusCode}), abandonné');
        }
        file = (prefs.getStringList(cleFile) ?? <String>[])..remove(brut);
        await prefs.setStringList(cleFile, file);
      }
    } catch (e) {
      // Réseau, session expirée : la file reste en place et repartira au
      // prochain relevé. C'est exactement ce pour quoi `collectedAt` existe.
      debugPrint('[GeoService] envoi différé : $e');
    } finally {
      _envoiEnCours = false;
    }
  }
}
