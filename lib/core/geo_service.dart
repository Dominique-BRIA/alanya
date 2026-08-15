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

  /// Clé du consentement, **par COMPTE**.
  ///
  /// 🐛 ELLE ÉTAIT GLOBALE AU TÉLÉPHONE, et c'était un défaut sérieux. Deux
  /// conséquences constatées sur un même appareil : un compte qui n'avait jamais
  /// été consulté héritait du « oui » d'un autre et se retrouvait suivi sans
  /// l'avoir accepté ; et à l'inverse, le compte qui revenait n'était plus
  /// jamais interrogé — l'écran de divulgation ne réapparaissait pas, même après
  /// une déconnexion.
  ///
  /// Un consentement appartient à une PERSONNE, pas à un morceau de matériel.
  ///
  /// ⚠️ L'ancienne clé globale n'est pas reprise : impossible de savoir QUI
  /// avait accepté. Ceux qui l'avaient fait seront donc consultés une fois de
  /// plus — c'est le comportement juste, pas une régression.
  static String _cleConsentement(String userId) => 'geo_consentement_$userId';

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

  /// Cadence en cours, ÉCRITE dans les préférences pour l'isolat.
  ///
  /// Il en a besoin pour rétablir le libellé exact du service de premier plan
  /// (« relevée toutes les N minutes ») quand la localisation revient alors que
  /// l'application est fermée. Sans elle, il devrait inventer un texte différent
  /// de celui posé par l'application.
  static const cleIntervalle = 'geo_intervalle_min';

  /// Libellés de la notification du service de premier plan.
  ///
  /// ⚠️ PUBLICS parce que l'ISOLAT les repose quand il constate le retour ou la
  /// coupure de la localisation, application fermée. Deux jeux de textes
  /// finiraient par diverger, et la notification changerait de mots selon
  /// l'isolat qui l'a écrite la dernière.
  static const titreServiceActif = "Alanya Work — localisation active";
  static const titreServicePause = "Alanya Work — suivi en pause";
  static const texteServicePause =
      "La localisation du téléphone est coupée : plus rien n'est relevé.";
  static const seuilDeplacementMetresDefaut = 75;
  static const intervalleHeartbeatMinDefaut = 5;

  static String texteServiceActif({int seuilMetres = 75, int heartbeatMin = 5}) =>
      "Votre position est relevée tous les $seuilMetres m (ou $heartbeatMin min d'immobilité).";

  static const cleDerniereLat = 'geo_derniere_lat';
  static const cleDerniereLon = 'geo_derniere_lon';
  static const cleDernierReleveTimeMs = 'geo_dernier_releve_time_ms';

  /// Détermine si un relevé doit être enregistré et envoyé (déplacement >= seuilMetres OU temps écoulé >= heartbeatMin).
  static Future<bool> doitEnregistrerEtEnvoyer(
    double lat,
    double lon,
    DateTime timestamp, {
    int seuilMetres = seuilDeplacementMetresDefaut,
    int heartbeatMin = intervalleHeartbeatMinDefaut,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final lastLat = prefs.getDouble(cleDerniereLat);
    final lastLon = prefs.getDouble(cleDerniereLon);
    final lastTimeMs = prefs.getInt(cleDernierReleveTimeMs);

    if (lastLat == null || lastLon == null || lastTimeMs == null) {
      return true;
    }

    final distance = Geolocator.distanceBetween(lastLat, lastLon, lat, lon);
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastTimeMs);
    final ecouleSec = timestamp.difference(lastTime).inSeconds;

    if (distance >= seuilMetres || ecouleSec >= heartbeatMin * 60) {
      return true;
    }

    return false;
  }

  /// Sauvegarde les coordonnées du dernier relevé validé.
  static Future<void> sauvegarderDernierReleve(
    double lat,
    double lon,
    DateTime timestamp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(cleDerniereLat, lat);
    await prefs.setDouble(cleDerniereLon, lon);
    await prefs.setInt(cleDernierReleveTimeMs, timestamp.millisecondsSinceEpoch);
  }

  Timer? _minuteur;
  StreamSubscription<Position>? _positionStreamSub;
  bool _envoiEnCours = false;

  /// Écoute de l'interrupteur de localisation du système. Voir
  /// [_surveilleLaLocalisation].
  StreamSubscription<ServiceStatus>? _surveillance;

  /// Veille qui REPOSE le rappel tant que la localisation est coupée. Voir
  /// [_signaleLocalisationCoupee].
  Timer? _veilleRappel;

  /// Cadence de cette veille.
  ///
  /// Une minute est un compromis assumé : c'est le délai maximum pendant lequel
  /// un utilisateur d'Android 14 peut faire disparaître le rappel en le
  /// balayant. Plus court n'apporterait rien de visible (la notification est
  /// silencieuse et sa pose coûte un appel de plateforme), plus long donnerait
  /// l'impression que le balayage a marché.
  static const _cadenceVeilleRappel = Duration(minutes: 1);

  /// Compte et cadence en cours, retenus pour pouvoir RELANCER la collecte
  /// quand la localisation est rétablie en cours de session — le flux système
  /// ne transporte pas ces informations.
  String? _userId;
  int _intervalleMin = 5;

  void init(AuthedApi api) => _api = api;

  // ── Consentement ─────────────────────────────────────────────────────────

  Future<ConsentementGeo> consentement(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_cleConsentement(userId))) {
      case 'accepte':
        return ConsentementGeo.accepte;
      case 'refuse':
        return ConsentementGeo.refuse;
      default:
        return ConsentementGeo.jamaisDemande;
    }
  }

  /// Enregistre la décision localement **et la remonte au serveur**.
  ///
  /// ⚠️ LA REMONTÉE N'EST PAS DÉCORATIVE : l'écran de divulgation promet à
  /// l'utilisateur que son entreprise sera informée si le suivi n'est pas actif.
  /// Tant que la décision ne vivait que dans les préférences du téléphone, cette
  /// phrase était une promesse que rien ne tenait.
  ///
  /// Le REFUS est même l'information la plus utile des deux : un compte sans
  /// relevé peut l'être parce qu'il a refusé, parce que son GPS est coupé, ou
  /// parce qu'il n'a pas ouvert l'application depuis deux jours. Sans cette
  /// remontée, l'entreprise ne pouvait pas distinguer trois situations très
  /// différentes.
  ///
  /// L'écriture locale d'abord, l'envoi ensuite : un réseau absent ne doit pas
  /// faire reposer la question à la prochaine ouverture.
  Future<void> enregistreConsentement(String userId, bool accepte) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _cleConsentement(userId), accepte ? 'accepte' : 'refuse');
    await _remonteConsentement(accepte);
  }

  Future<void> _remonteConsentement(bool accepte) async {
    try {
      await _api?.post('/api/geo/consentement', {'accepte': accepte});
    } catch (e) {
      // Réseau absent : la décision reste locale et sera ré-affirmée à la
      // prochaine connexion — `demarrer` la renvoie à chaque démarrage.
      debugPrint('[GeoService] consentement non remonté : $e');
    }
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

  /// Surveille l'interrupteur de localisation du système, EN COURS DE ROUTE.
  ///
  /// ⚠️ SANS ELLE, LE RAPPEL N'ARRIVAIT QU'AU LANCEMENT SUIVANT. Quelqu'un qui
  /// coupe sa localisation à midi sans fermer l'application n'était prévenu
  /// qu'au prochain démarrage — il pouvait passer la journée à se croire suivi
  /// sans l'être. C'est exactement le silence que ce rappel existe pour rompre.
  ///
  /// Le flux est fourni par le système : aucun sondage, aucune batterie
  /// consommée à interroger un interrupteur.
  void _surveilleLaLocalisation() {
    _surveillance ??= Geolocator.getServiceStatusStream().listen((statut) {
      if (statut == ServiceStatus.disabled) {
        debugPrint('[GeoService] localisation coupée en cours de route');
        // Permanent sans condition ici : on RELEVAIT jusqu'à cet instant, donc
        // la permission est forcément accordée et le service de premier plan
        // tourne — les deux conditions qui rendent le rappel retirable.
        unawaited(_signaleLocalisationCoupee(permanent: true));
        return;
      }

      /*
       * 🐛 RALLUMÉE : IL NE SUFFIT PAS DE RETIRER LA NOTIFICATION.
       *
       * Le commentaire précédent affirmait « le minuteur n'ayant jamais cessé ».
       * C'était FAUX dans le cas qui compte : quand l'application démarre alors
       * que la localisation est déjà coupée, `demarrer` sort par son contrôle de
       * permissions AVANT d'armer le minuteur et le service de premier plan.
       * Rien ne tournait donc, et retirer le rappel se contentait d'effacer le
       * seul signe visible du problème — l'utilisateur voyait la notification
       * disparaître, en concluait que tout allait bien, et rien n'était collecté
       * jusqu'au prochain lancement.
       *
       * On relance donc réellement. `demarrer` est idempotent : son contrôle
       * `_minuteur != null` empêche d'empiler un second minuteur si la collecte
       * tournait déjà, et l'abonnement à ce flux est protégé par `??=`.
       */
      unawaited(_localisationRevenue());
    });
  }

  /// Signale que la localisation est coupée, et **fait en sorte que ça se voie
  /// tant que ça dure**.
  ///
  /// 🔴 LE DRAPEAU `ongoing` NE SUFFIT PAS, ET C'EST LA RAISON D'ÊTRE DE CETTE
  /// VEILLE. Jusqu'à Android 13, une notification `ongoing` ne se balaie pas :
  /// le drapeau tient seul la promesse. **Depuis Android 14, l'utilisateur peut
  /// la balayer** — le système ne réserve plus l'exception qu'aux appels, aux
  /// sessions média et aux applications de gestion d'entreprise. Reposer la
  /// notification est donc le seul moyen restant de tenir « non balayable ».
  ///
  /// La veille sert aussi de second filet à la détection : elle relit
  /// l'interrupteur elle-même, donc un événement du flux système perdu (isolat
  /// suspendu, constructeur trop zélé) ne laisse pas le rappel affiché après le
  /// retour de la localisation.
  ///
  /// ⚠️ `permanent: false` quand rien ne pourra la retirer — voir [demarrer].
  Future<void> _signaleLocalisationCoupee({required bool permanent}) async {
    /*
     * Le minuteur s'arrête : sans interrupteur, chaque relevé partirait quand
     * même pour rester pendu 45 secondes sur un GPS qui ne répondra pas — de la
     * batterie dépensée à échouer. C'est aussi ce qui permet à
     * `_localisationRevenue` de relancer VRAIMENT : `demarrer` sort par son
     * contrôle `_minuteur != null`, donc tant qu'un minuteur mort traîne, le
     * retour de la localisation ne rétablirait ni la collecte ni le libellé du
     * service de premier plan.
     */
    _minuteur?.cancel();
    _minuteur = null;
    await _marqueServiceEnPause();
    await PushService.instance.showRappelLocalisation(permanent: permanent);
    if (!permanent) return;
    _veilleRappel ??= Timer.periodic(_cadenceVeilleRappel, (_) async {
      if (await Geolocator.isLocationServiceEnabled()) {
        await _localisationRevenue();
        return;
      }
      await PushService.instance.showRappelLocalisation(permanent: true);
    });
  }

  /// La localisation est revenue : retirer le rappel, arrêter la veille, et
  /// **relancer réellement la collecte**.
  ///
  /// 🐛 IL NE SUFFIT PAS DE RETIRER LA NOTIFICATION. Quand l'application démarre
  /// alors que la localisation est déjà coupée, `demarrer` sort par son contrôle
  /// de permissions AVANT d'armer le minuteur : rien ne tourne, et effacer le
  /// rappel effacerait le seul signe visible du problème — l'utilisateur en
  /// conclurait que tout va bien pendant que rien n'est collecté.
  ///
  /// `demarrer` est idempotent (`_minuteur != null`), donc l'appeler ici ne
  /// risque pas d'empiler un second minuteur si la collecte tournait déjà.
  Future<void> _localisationRevenue() async {
    _veilleRappel?.cancel();
    _veilleRappel = null;
    await PushService.instance.retireRappelLocalisation();
    final userId = _userId;
    if (userId == null) return;
    debugPrint('[GeoService] localisation rétablie — relance de la collecte');
    await demarrer(userId: userId, intervalleMin: _intervalleMin);
  }

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
  ///
  /// ⚠️ LA GARDE `_minuteur != null` NE SUFFIT PLUS À ELLE SEULE depuis que le
  /// retour de la localisation relance la collecte : le flux système et la
  /// veille peuvent le constater au même instant, et deux appels partiraient en
  /// parallèle. Or `_minuteur` n'est posé qu'à la toute fin, après plusieurs
  /// attentes (préférences, permissions) — les deux passeraient donc la garde
  /// et armeraient chacun un minuteur, doublant la cadence des relevés à vie.
  bool _demarrageEnCours = false;

  Future<void> demarrer({
    required String userId,
    required int intervalleMin,
  }) async {
    if (_minuteur != null || _demarrageEnCours) return;
    _demarrageEnCours = true;
    try {
      await _demarre(userId: userId, intervalleMin: intervalleMin);
    } finally {
      _demarrageEnCours = false;
    }
  }

  Future<void> _demarre({
    required String userId,
    required int intervalleMin,
  }) async {
    if (await consentement(userId) != ConsentementGeo.accepte) return;
    // Retenus AVANT toute sortie anticipée : c'est précisément quand `demarrer`
    // échoue sur les permissions que la surveillance aura besoin de relancer.
    _userId = userId;
    _intervalleMin = intervalleMin > 0 ? intervalleMin : 5;
    final periode = Duration(minutes: _intervalleMin);
    // Déposée pour l'isolat, qui doit pouvoir rétablir le même libellé.
    await _memoriseIntervalle(_intervalleMin);
    // Ré-affirmée à chaque démarrage : c'est ce qui rattrape une remontée
    // perdue faute de réseau au moment du choix.
    unawaited(_remonteConsentement(true));
    _surveilleLaLocalisation();
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
       *
       * 🔴 DEUX ÉCHECS TRÈS DIFFÉRENTS SE CACHENT DERRIÈRE CE SEUL `false`, et
       * ils n'appellent pas le même rappel :
       *
       * — L'INTERRUPTEUR est coupé, la permission étant accordée : c'est
       *   exactement le cas visé, le rappel est **permanent**. On peut le
       *   promettre parce qu'on garde les moyens de le retirer — le service de
       *   premier plan a le droit de démarrer et fera la veille même
       *   application fermée.
       *
       * — La PERMISSION est refusée : le service de premier plan de type
       *   `location` ne peut pas démarrer (Android 14 le refuse net), donc
       *   personne ne veillera une fois l'application fermée. Un rappel non
       *   balayable resterait alors affiché À VIE, y compris longtemps après
       *   que l'utilisateur a tout réglé. On le laisse balayable : une
       *   notification qu'on ne peut plus retirer est pire que le silence.
       *   ⚠️ `demandePermissions` sort sur l'interrupteur AVANT de regarder la
       *   permission — les deux peuvent donc être en cause à la fois, d'où le
       *   contrôle explicite des deux ici.
       */
      final interrupteurCoupe = !await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      final permissionAccordee = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      final permanent = interrupteurCoupe && permissionAccordee;
      await _signaleLocalisationCoupee(permanent: permanent);
      // La vigie : le service tourne sans rien relever, uniquement pour
      // reposer le rappel et le retirer quand la localisation reviendra.
      if (permanent) {
        await _demarreServicePremierPlan(periode, localisationCoupee: true);
      }
      return;
    }

    // Écoute continue des déplacements >= 75 mètres via la position stream
    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: seuilDeplacementMetresDefaut,
      ),
    ).listen((position) {
      unawaited(_traiteNouvellePosition(position));
    });

    // Un premier relevé heartbeat tout de suite au démarrage
    unawaited(_releveHeartbeat());

    // Minuteur récurrent (chaque minute) pour vérifier le heartbeat des 5 minutes d'immobilité
    _minuteur = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_releveHeartbeat()),
    );
    await _demarreServicePremierPlan(periode);
    debugPrint('[GeoService] relevé démarré (seuil $seuilDeplacementMetresDefaut m / heartbeat $_intervalleMin min)');
  }

  Future<void> _memoriseIntervalle(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(cleIntervalle, minutes);
    } catch (_) {}
  }

  /// Met le libellé du service de premier plan en accord avec la réalité.
  ///
  /// ⚠️ SANS ÇA, LA NOTIFICATION PERMANENTE MENT. Elle annonce « votre position
  /// est relevée toutes les 5 minutes » alors que l'interrupteur est coupé et
  /// que rien n'est relevé — c'est-à-dire qu'elle rassure précisément au moment
  /// où il faudrait alerter. Le service, lui, continue de tourner : il n'est pas
  /// lié à l'interrupteur, et on a besoin qu'il vive pour tenir la veille.
  ///
  /// Le chemin inverse n'existe pas ici : le libellé actif est reposé par
  /// [_demarreServicePremierPlan], que la relance traverse de toute façon.
  Future<void> _marqueServiceEnPause() async {
    if (!Platform.isAndroid) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: titreServicePause,
        notificationText: texteServicePause,
      );
    } catch (e) {
      debugPrint('[GeoService] libellé du service inchangé : $e');
    }
  }

  /// Arrête le relevé. À appeler à la déconnexion — sans quoi le téléphone
  /// continuerait de rapporter la position d'un compte qui n'est plus là.
  Future<void> arreter() async {
    _minuteur?.cancel();
    _minuteur = null;
    await _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _veilleRappel?.cancel();
    _veilleRappel = null;
    await _surveillance?.cancel();
    _surveillance = null;
    // Sans cet oubli, la surveillance d'une session suivante pourrait relancer
    // la collecte au nom du compte qui vient de partir.
    _userId = null;

    /*
     * ⚠️ L'ORDRE COMPTE, ET IL A CHANGÉ : LE SERVICE D'ABORD, LA NOTIFICATION
     * ENSUITE. L'isolat repose le rappel à chaque cycle tant que la localisation
     * est coupée ; le retirer avant de l'arrêter laisserait une fenêtre où il le
     * repose juste après. Et comme ce rappel n'est plus balayable, la personne
     * qui vient de se déconnecter se retrouverait avec, sur son écran, une
     * notification définitive qu'aucun code ne viendrait plus jamais enlever.
     */
    if (Platform.isAndroid) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    }
    // Le rappel appartenait au compte qui part : le laisser afficher
    // « activez votre localisation » à qui vient de se déconnecter n'a aucun
    // sens, et le suivant n'est peut-être même pas concerné.
    await PushService.instance.retireRappelLocalisation();
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
  Future<void> _demarreServicePremierPlan(
    Duration periode, {
    bool localisationCoupee = false,
  }) async {
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
          eventAction: ForegroundTaskEventAction.repeat(const Duration(minutes: 1).inMilliseconds),
          // Reprend après un redémarrage du téléphone : sans cela, la collecte
          // s'arrêterait la nuit et ne repartirait qu'à la prochaine ouverture.
          autoRunOnBoot: true,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      final titre = localisationCoupee ? titreServicePause : titreServiceActif;
      final texte =
          localisationCoupee ? texteServicePause : texteServiceActif();

      /*
       * ⚠️ DÉMARRER UN SERVICE DÉJÀ DÉMARRÉ N'EST PAS ANODIN : `startService`
       * échoue quand le service tourne, et le libellé resterait alors celui
       * posé la première fois — c'est-à-dire « localisation active » sur un
       * téléphone dont l'interrupteur est coupé. Or on repasse ici à chaque
       * relance, la principale étant justement le retour de la localisation.
       */
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: titre,
          notificationText: texte,
        );
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: titre,
        notificationText: texte,
        callback: pointEntreeTacheGeo,
      );
    } catch (e) {
      // Service refusé par le système (permission manquante, constructeur
      // restrictif) : le relevé continue tant que l'application vit. Mieux vaut
      // une trace partielle que pas de trace du tout.
      debugPrint('[GeoService] service de premier plan indisponible : $e');
    }
  }

  Future<void> _traiteNouvellePosition(Position position) async {
    final timestamp = position.timestamp;
    final doitEnvoyer = await doitEnregistrerEtEnvoyer(
      position.latitude,
      position.longitude,
      timestamp,
      seuilMetres: seuilDeplacementMetresDefaut,
      heartbeatMin: _intervalleMin,
    );

    if (doitEnvoyer) {
      await sauvegarderDernierReleve(
        position.latitude,
        position.longitude,
        timestamp,
      );

      await _envoieOuMetEnFile({
        'lat': position.latitude,
        'lon': position.longitude,
        'collectedAt': timestamp.toUtc().toIso8601String(),
      });
    }
  }

  Future<void> _releveHeartbeat() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 45),
        ),
      );
      await _traiteNouvellePosition(position);
    } catch (e) {
      debugPrint('[GeoService] relevé heartbeat impossible : $e');
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
