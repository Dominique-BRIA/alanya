import 'package:flutter/foundation.dart';

import 'e2ee_media.dart';
import 'e2ee_service.dart';

/// Ce qu'il faut pour rechiffrer un de MES messages : son clair, tel que mon
/// cache le garde.
class ClairARenvoyer {
  const ClairARenvoyer({
    required this.texte,
    this.media,
    this.reponseA,
    this.genre,
  });

  final String texte;
  final DescripteurMedia? media;
  final String? reponseA;

  /// CONTACT, LOCATION, STICKER… ; nul pour un texte ou un média.
  final String? genre;
}

typedef AppelRenvois = Future<Map<String, dynamic>> Function(
  String methode,
  String chemin,
  Map<String, dynamic>? corps,
);

/// Exécute une action sous un verrou (voir `VerrouReleve.sous`).
typedef Verrou = Future<T> Function<T>(Future<T> Function() action);

/*
 * 🔴 PISTE B (14/11/2026) : LE RENVOI PAR L'EXPÉDITEUR.
 *
 * Un message chiffré pour mes seuls anciens appareils, qu'aucun n'a relevé,
 * est illisible ici : personne ne l'a chiffré pour cet appareil. Je le
 * DEMANDE ([demander]) ; le serveur choisit lui-même les messages éligibles et
 * prévient leurs expéditeurs. Un appareil de l'expéditeur retrouve le clair
 * dans SON cache, le rechiffre pour le seul appareil demandeur et le dépose
 * ([servir]). La relève ordinaire remplit ensuite la bulle.
 *
 * ⚠️ LE CHIFFREMENT NE CHANGE PAS : le renvoi ne part que vers un appareil
 * publié du compte destinataire, avec ses clés publiées, comme un envoi
 * ordinaire.
 *
 * Sorti de `PileE2ee` le 15/11/2026 pour être éprouvé sans application :
 * `test/e2ee_renvois_test.dart`.
 */
class RenvoisE2ee {
  RenvoisE2ee({
    required this.api,
    required this.service,
    required this.monAppareil,
    required this.lireClairs,
    this.verrou,
  });

  final AppelRenvois api;
  final E2eeService service;
  final Future<int> Function() monAppareil;

  /// Les clairs de MES messages dans ce fil, par identifiant de message.
  final Future<Map<String, ClairARenvoyer>> Function(String convId) lireClairs;

  /// Rechiffrer avance la même session qu'une relève lirait.
  final Verrou? verrou;

  /// Demande au serveur les messages qui manquent à cet appareil.
  ///
  /// ⚠️ NE LÈVE JAMAIS : serveur ancien ou réseau coupé, on redemandera au
  /// prochain lancement. Rend le nombre de demandes enregistrées.
  Future<int> demander() async {
    try {
      final r = await api('POST', '/api/e2ee/renvois', {'deviceId': await monAppareil()});
      return (r['demandes'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _enCours = false;

  /// Sert les demandes qui visent MES messages. Rend le nombre servi.
  ///
  /// ⚠️ NE LÈVE JAMAIS, et une demande qui échoue n'arrête pas les autres.
  Future<int> servir() async {
    if (_enCours) return 0;
    _enCours = true;
    var servis = 0;
    try {
      final r = await api('GET', '/api/e2ee/renvois', null);
      final demandes = ((r['demandes'] as List?) ?? const []).cast<Map>();
      if (demandes.isEmpty) return 0;
      final appareilEnvoi = await monAppareil();
      final fils = <String, Map<String, ClairARenvoyer>>{};

      Future<void> tout() async {
        for (final d in demandes) {
          try {
            final convId = d['convId'] as String;
            final messageId = d['messageId'] as String;
            final demandeur = d['demandeurId'] as String;
            final appareil = d['demandeurDevice'] as int;
            final clairs = fils[convId] ??= await lireClairs(convId);
            final c = clairs[messageId];
            // Le clair n'est plus ici : un autre de mes appareils l'a peut-être.
            if (c == null) continue;
            if (c.media == null && c.texte.isEmpty) continue;
            final charge = ecrireCharge(messageId, c.texte, c.media, c.reponseA, c.genre);
            final appareils = await service.ouvrirSessions(demandeur);
            // L'appareil demandeur n'est plus publié : rien à servir.
            if (!appareils.contains(appareil)) continue;
            final e = await service.chiffrer(demandeur, appareil, charge);
            await api('POST', '/api/e2ee/renvois/servir', {
              'id': d['id'],
              'deviceId': appareilEnvoi,
              'type': e.type,
              'corps': e.corps,
            });
            servis++;
          } catch (e) {
            debugPrint("[e2ee] renvoi impossible : $e");
          }
        }
      }

      final v = verrou;
      if (v == null) {
        await tout();
      } else {
        await v(tout);
      }
    } catch (_) {
      // Serveur ancien ou réseau coupé : au prochain lancement.
    } finally {
      _enCours = false;
    }
    return servis;
  }
}
