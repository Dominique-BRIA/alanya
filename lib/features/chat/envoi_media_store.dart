import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;

import '../../core/api_client.dart';
import '../../core/connectivity_service.dart';
import '../../core/centre_transferts.dart';
import '../../core/realtime_client.dart';
import '../media/media_repository.dart';
import 'chat_repository.dart';
import 'envoi_media.dart';
import 'envois_persistes.dart';

/// File des envois de médias, **hors de l'écran de discussion**.
///
/// 🐛 **POURQUOI CE DÉPLACEMENT** (signalé sur device le 17/08/2026) : « j'envoie
/// un média, je sors de la conversation, je reviens : ça a disparu, je ne vois
/// rien ». La file vivait dans l'état de `ChatScreen`. Quitter l'écran le
/// détruit — et avec lui la file, la progression, et la bulle provisoire. Pire :
/// le téléversement en cours continuait dans le vide, puisque la suite du code
/// touchait le `context` d'un écran mort ; le message n'était donc parfois même
/// pas envoyé. Un envoi ne peut pas dépendre de la présence d'un écran.
///
/// Ici, la file survit à la navigation : l'écran s'y ABONNE quand il existe, et
/// l'envoi se poursuit quand il n'existe plus.
///
/// ⚠️ **Singleton assumé**, comme `RingtoneService`, `PushService` ou
/// `MediaCache` dans ce projet. Un envoi n'appartient pas à un écran, et le
/// faire descendre par l'arbre de widgets reviendrait à le rattacher à celui qui
/// se trouve à l'écran au moment du clic — c'est-à-dire au problème d'origine.
/// Les dépendances (dépôts, temps réel) sont fournies AU LANCEMENT plutôt
/// qu'injectées : ainsi ce magasin ne détient jamais de `BuildContext`.
class EnvoiMediaStore extends ChangeNotifier {
  EnvoiMediaStore._();
  static final EnvoiMediaStore instance = EnvoiMediaStore._();

  final Map<String, EnvoiMedia> _envois = {};
  final Map<String, Timer> _attentesEcho = {};

  /*
   * LES SERVICES DU DERNIER LANCEMENT, retenus pour repartir tout seul.
   *
   * ⚠️ AUCUN `BuildContext` ICI, et c'est la regle que ce magasin s'est fixee
   * des l'origine. Ce sont des depots et des clients construits une fois au
   * demarrage de l'application, dans `main.dart` : les garder ne rattache
   * l'envoi a aucun ecran, et c'est justement ce qui lui permet de continuer
   * quand plus aucun ecran n'existe.
   *
   * Sans eux, une reprise automatique serait impossible : le retour du reseau
   * n'arrive jamais pendant qu'un ecran nous tend ses services.
   */
  MediaRepository? _media;
  ChatRepository? _chat;
  RealtimeClient? _rt;
  ConnectivityService? _conn;
  String Function()? _messageErreurGenerique;

  /// La relecture sur disque n'a lieu qu'UNE FOIS par lancement.
  bool _restaure = false;

  /// Branche les services et REPREND ce qui attendait avant la fermeture.
  ///
  /// 🔴 APPELE AU DEMARRAGE DE L'APPLICATION, et c'est indispensable. Sans lui,
  /// les envois relus du disque seraient bien affiches mais ne partiraient
  /// JAMAIS : la reprise a besoin des depots, et ceux-ci n'arrivaient jusqu'ici
  /// qu'au moment ou un ecran lancait un envoi. Or apres un redemarrage, aucun
  /// envoi n'est lance — c'est justement le probleme a resoudre.
  ///
  /// ⚠️ Les services passes ici sont construits une fois dans `main.dart` : ce
  /// magasin ne detient toujours aucun `BuildContext`.
  Future<void> brancher({
    required MediaRepository media,
    required ChatRepository chat,
    required RealtimeClient rt,
    required ConnectivityService conn,
    String Function()? messageErreurGenerique,
  }) async {
    _media = media;
    _chat = chat;
    _rt = rt;
    _messageErreurGenerique ??=
        messageErreurGenerique ?? () => "Échec de l'envoi";
    if (!identical(conn, _conn)) {
      _conn?.removeListener(_auRetourDuReseau);
      _conn = conn;
      conn.addListener(_auRetourDuReseau);
    }

    if (_restaure) return;
    _restaure = true;

    final repris = await EnvoisPersistes.charger();
    if (repris.isEmpty) return;
    for (final e in repris) {
      // `putIfAbsent` : un envoi lance depuis un ecran pendant la relecture ne
      // doit pas etre ecrase par sa copie disque, plus ancienne.
      _envois.putIfAbsent(e.tempId, () => e);
    }
    notifyListeners();
    _auRetourDuReseau();
  }

  /// Envois — en cours ou échoués — d'une conversation, du plus ancien au plus
  /// récent. C'est ce que l'écran ajoute au fil sous forme de bulles.
  List<EnvoiMedia> pour(String convId) {
    final liste = _envois.values.where((e) => e.convId == convId).toList()
      ..sort((a, b) => a.creeA.compareTo(b.creeA));
    return liste;
  }

  EnvoiMedia? parTempId(String tempId) => _envois[tempId];

  bool get vide => _envois.isEmpty;

  /// Retire un envoi abouti. Appelé à la réception de l'écho du serveur, qui est
  /// la seule preuve que le message existe vraiment.
  void terminer(String tempId) {
    _attentesEcho.remove(tempId)?.cancel();
    // Les octets ne servent plus a rien : ni le disque ni la memoire ne doivent
    // les garder.
    unawaited(EnvoisPersistes.oublier(tempId));
    // La notification disparaît : la preuve de l'envoi est la bulle dans la
    // conversation, pas une ligne « terminé » à balayer.
    CentreTransferts.instance.reussir(tempId);
    if (_envois.remove(tempId) != null) notifyListeners();
  }

  /// Abandonne un envoi échoué.
  ///
  /// Les médias déjà téléversés deviennent alors orphelins côté serveur — mais
  /// c'est un choix EXPLICITE de l'utilisateur, pas une perte silencieuse.
  void abandonner(String tempId) => terminer(tempId);

  /// Lance (ou relance) un envoi. Reprend là où un échec précédent s'est arrêté.
  ///
  /// Les trois services sont passés par l'appelant, qui les lit dans son
  /// `context` AVANT tout `await` : ce magasin n'en garde aucune référence à un
  /// arbre de widgets.
  Future<void> lancer(
    EnvoiMedia envoi, {
    required MediaRepository media,
    required ChatRepository chat,
    required RealtimeClient rt,
    required String Function() messageErreurGenerique,
    ConnectivityService? conn,
  }) async {
    _media = media;
    _chat = chat;
    _rt = rt;
    _messageErreurGenerique = messageErreurGenerique;
    if (conn != null && !identical(conn, _conn)) {
      _conn?.removeListener(_auRetourDuReseau);
      _conn = conn;
      conn.addListener(_auRetourDuReseau);
    }

    _envois[envoi.tempId] = envoi;
    envoi.echoue = false;
    envoi.enAttenteReseau = false;
    envoi.erreur = null;
    notifyListeners();

    // La progression sort de l'application : elle se suit désormais dans les
    // notifications, sans ouvrir Alanya. Le libellé dit le NOMBRE de fichiers
    // plutôt que leurs noms — « photo_2026_08_19_143022.jpg » ne rentre pas et
    // n'apprend rien.
    CentreTransferts.instance.demarrer(
      id: envoi.tempId,
      sorte: SorteTransfert.envoi,
      titre: envoi.total > 1 ? "${envoi.total} fichiers" : _nomLisible(envoi),
      fraction: envoi.progression,
    );

    try {
      for (var i = envoi.mediaIdsObtenus.length;
          i < envoi.fichiers.length;
          i++) {
        final f = envoi.fichiers[i];
        envoi.indexCourant = i;
        envoi.progressionFichier = 0;
        notifyListeners();

        final envoye = await media.upload(
          Uint8List.fromList(f.bytes),
          f.fileName,
          f.mimeType,
          durationMs: f.durationMs,
          onProgress: (envoyes, total) {
            if (total <= 0) return;
            final ratio = envoyes / total;
            // Un avis par trame réseau redessinerait le fil des centaines de
            // fois : on ne remonte qu'au changement de centième.
            if ((ratio - envoi.progressionFichier).abs() < 0.01 && ratio < 1) {
              return;
            }
            envoi.progressionFichier = ratio;
            CentreTransferts.instance.avancer(envoi.tempId, envoi.progression);
            notifyListeners();
          },
        );
        envoi.mediaIdsObtenus.add(envoye.id);
        CentreTransferts.instance.avancer(envoi.tempId, envoi.progression);
        notifyListeners();
      }

      if (rt.connected) {
        rt.sendMultiMedia(
            envoi.convId, envoi.mediaIdsObtenus, envoi.msgType, envoi.tempId,
            replyToId: envoi.replyToId,
            content: envoi.legende,
            mentions: envoi.mentions);
        _armeAttenteEcho(envoi);
      } else {
        await chat.sendMultiMedia(
            envoi.convId, envoi.mediaIdsObtenus, envoi.msgType,
            replyToId: envoi.replyToId,
            content: envoi.legende,
            mentions: envoi.mentions);
        // Le repli REST rend le message créé : l'envoi est terminé, l'écran le
        // rechargera par ses voies normales.
        terminer(envoi.tempId);
      }
    } on ApiException catch (e) {
      _echec(envoi, e.message);
    } catch (e) {
      if (_estPanneReseau(e)) {
        _enAttente(envoi);
      } else {
        _echec(envoi, messageErreurGenerique());
      }
    }
  }

  /// L'envoi attend le reseau. Aucune alerte, aucune decision a prendre.
  ///
  /// ⚠️ LA NOTIFICATION DE TRANSFERT EST RETIREE SANS ETRE MARQUEE EN ECHEC.
  /// `CentreTransferts.echouer` affiche une ligne rouge persistante, qu'il faut
  /// balayer a la main : exactement ce que l'utilisateur n'a pas a faire ici.
  /// Elle reparaitra d'elle-meme quand l'envoi repartira.
  ///
  /// ⚠️ `mediaIdsObtenus` EST CONSERVE, comme pour un echec : les fichiers deja
  /// televerses avant la coupure ne repartiront pas une seconde fois.
  void _enAttente(EnvoiMedia envoi) {
    envoi.echoue = false;
    envoi.enAttenteReseau = true;
    envoi.erreur = null;
    envoi.progressionFichier = 0;
    CentreTransferts.instance.reussir(envoi.tempId);
    notifyListeners();
    // Sur disque : le systeme peut tuer l'application avant le retour du reseau,
    // et c'est le cas NORMAL quand elle passe en arriere-plan.
    unawaited(EnvoisPersistes.enregistrer(envoi));
  }

  /// Le reseau est revenu : tout ce qui attendait repart, dans l'ordre.
  ///
  /// ⚠️ SEQUENTIEL, PAS EN PARALLELE. Dix envois relances d'un coup se
  /// partageraient la bande passante d'une connexion qui vient tout juste de
  /// revenir — et arriveraient dans le desordre. On les enchaine.
  void _auRetourDuReseau() {
    final conn = _conn;
    if (conn == null || !conn.isOnline) return;
    final media = _media;
    final chat = _chat;
    final rt = _rt;
    final message = _messageErreurGenerique;
    if (media == null || chat == null || rt == null || message == null) return;

    final aRelancer =
        _envois.values.where((e) => e.enAttenteReseau).toList()
          ..sort((a, b) => a.creeA.compareTo(b.creeA));
    if (aRelancer.isEmpty) return;

    unawaited(() async {
      for (final envoi in aRelancer) {
        if (!conn.isOnline) break;
        // `lancer` reprend a `mediaIdsObtenus.length` : rien n'est refait.
        await lancer(envoi,
            media: media,
            chat: chat,
            rt: rt,
            messageErreurGenerique: message,
            conn: conn);
      }
    }());
  }

  /// L'ECHEC VIENT-IL DU RESEAU, ou le serveur a-t-il REFUSE ?
  ///
  /// 🔴 TOUTE LA DIFFERENCE EST LA. Un refus du serveur — fichier trop lourd,
  /// correspondant bloque, conversation disparue — ne se repare pas en
  /// reessayant : il faut le dire et laisser l'utilisateur decider. Une panne de
  /// reseau se repare toute seule des que la connexion revient : l'annoncer
  /// comme une erreur, avec une croix rouge et un bouton, demande d'agir la ou
  /// il n'y a rien a faire.
  ///
  /// ⚠️ `ApiException` NE SIGNIFIE QUE « LE SERVEUR A REPONDU ≥400 » — c'est le
  /// seul cas ou `api_client` la leve. Une coupure remonte telle quelle, en
  /// `SocketException` ou `ClientException`. Le type suffit donc a trancher.
  ///
  /// ⚠️ ON NE TRAITE PAS N'IMPORTE QUELLE EXCEPTION COMME UNE PANNE. Une erreur
  /// de programmation prise pour une coupure laisserait la bulle tourner
  /// indefiniment, sans que rien ne dise pourquoi. On nomme donc les trois
  /// formes possibles, et tout le reste reste un echec.
  bool _estPanneReseau(Object e) {
    if (e is ApiException) return false;
    return e is SocketException || e is ClientException || e is TimeoutException;
  }

  /// Nom court du premier fichier, pour la notification.
  String _nomLisible(EnvoiMedia envoi) {
    final nom = envoi.fichiers.isEmpty ? "" : envoi.fichiers.first.fileName;
    if (nom.isEmpty) return "Fichier";
    // Un nom d'appareil photo tient sur 30 caractères de bruit : on garde la
    // fin, qui porte l'extension, plutôt que le début qui n'apprend rien.
    return nom.length <= 28 ? nom : "…${nom.substring(nom.length - 27)}";
  }

  void _echec(EnvoiMedia envoi, String message) {
    // Les médias déjà téléversés RESTENT dans `mediaIdsObtenus` : c'est ce qui
    // permet au réessai de ne pas les envoyer une seconde fois.
    envoi.echoue = true;
    envoi.enAttenteReseau = false;
    envoi.erreur = message;
    envoi.progressionFichier = 0;
    // L'échec, LUI, reste affiché : un envoi qui disparaît sans rien dire fait
    // croire qu'il est parti.
    CentreTransferts.instance.echouer(envoi.tempId);
    notifyListeners();
    // Un echec attend une decision de l'utilisateur, qui peut ne venir que
    // demain : lui aussi doit survivre a la fermeture de l'application.
    unawaited(EnvoisPersistes.enregistrer(envoi));
  }

  /// Borne l'attente de l'écho du serveur pour un envoi parti par WebSocket.
  ///
  /// Une trame `send` n'a aucun accusé : si la socket tombe juste après, elle
  /// est perdue en silence et la bulle resterait « Envoi… » à vie.
  void _armeAttenteEcho(EnvoiMedia envoi) {
    _attentesEcho[envoi.tempId]?.cancel();
    _attentesEcho[envoi.tempId] = Timer(const Duration(seconds: 30), () {
      if (!_envois.containsKey(envoi.tempId)) return; // l'écho est arrivé
      // ⚠️ Le message a PEUT-ÊTRE été enregistré : c'est l'écho qui manque, pas
      // nécessairement l'écriture. Un réessai pourrait donc créer un doublon —
      // d'où le choix laissé à l'utilisateur, et un libellé qui parle de
      // confirmation et non d'échec.
      _echec(envoi, "Pas de confirmation du serveur");
    });
  }
}
