import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/realtime_client.dart';
import '../media/media_repository.dart';
import 'chat_repository.dart';
import 'envoi_media.dart';

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
  }) async {
    _envois[envoi.tempId] = envoi;
    envoi.echoue = false;
    envoi.erreur = null;
    notifyListeners();

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
            notifyListeners();
          },
        );
        envoi.mediaIdsObtenus.add(envoye.id);
        notifyListeners();
      }

      if (rt.connected) {
        rt.sendMultiMedia(
            envoi.convId, envoi.mediaIdsObtenus, envoi.msgType, envoi.tempId,
            replyToId: envoi.replyToId, content: envoi.legende);
        _armeAttenteEcho(envoi);
      } else {
        await chat.sendMultiMedia(
            envoi.convId, envoi.mediaIdsObtenus, envoi.msgType,
            replyToId: envoi.replyToId, content: envoi.legende);
        // Le repli REST rend le message créé : l'envoi est terminé, l'écran le
        // rechargera par ses voies normales.
        terminer(envoi.tempId);
      }
    } on ApiException catch (e) {
      _echec(envoi, e.message);
    } catch (_) {
      _echec(envoi, messageErreurGenerique());
    }
  }

  void _echec(EnvoiMedia envoi, String message) {
    // Les médias déjà téléversés RESTENT dans `mediaIdsObtenus` : c'est ce qui
    // permet au réessai de ne pas les envoyer une seconde fois.
    envoi.echoue = true;
    envoi.erreur = message;
    envoi.progressionFichier = 0;
    notifyListeners();
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
