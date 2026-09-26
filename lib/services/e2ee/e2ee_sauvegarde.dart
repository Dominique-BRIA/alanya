/// LA SAUVEGARDE CHIFFRÉE, CÔTÉ MOBILE — ticket 4.14.
///
/// 🔴 JUMEAU DE `STAGE-WEB/src/services/e2ee-sauvegarde.ts`. Les deux clients
/// parlent aux mêmes routes et au même format : une archive créée sur le web
/// doit s'ouvrir sur le téléphone, et l'inverse.
///
/// ⚠️ ACTIVÉE PAR DÉFAUT, comme sur le web (décision du user, 23/09/2026).
/// Perdre son historique en changeant d'appareil est un piège que personne ne
/// voit venir : le défaut doit protéger, pas attendre qu'on sache qu'il faut se
/// protéger.
///
/// ⚠️ ET UN REFUS TIENT. Le serveur mémorise « refusée » sur le COMPTE : un
/// téléphone neuf ne doit pas recréer la sauvegarde que quelqu'un vient de
/// supprimer depuis le web.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'e2ee_serrures.dart';

typedef AppelApi = Future<Map<String, dynamic>> Function(
  String methode,
  String chemin,
  Map<String, dynamic>? corps,
);

class E2eeSauvegarde {
  E2eeSauvegarde(this._api);

  final AppelApi _api;

  Uint8List? _maitresse;

  bool get estOuverte => _maitresse != null;

  /* ══════════════ LE COFFRE ══════════════ */

  /// Les serrures posées sur ce compte, et si la sauvegarde a été REFUSÉE.
  ///
  /// ⚠️ « PAS ENCORE ACTIVÉE » ET « REFUSÉE » NE SE CONFONDENT PAS : la première
  /// appelle une activation, la seconde l'interdit. Les traiter pareil ferait
  /// réapparaître la sauvegarde chez quelqu'un qui vient de la supprimer.
  Future<({List<Serrure> serrures, bool refusee})> lireCoffre() async {
    try {
      final r = await _api('GET', '/api/e2ee/coffre', null);
      final liste = (r['serrures'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Serrure.depuisJson)
          .toList();
      return (serrures: liste, refusee: r['refusee'] == true);
    } catch (_) {
      /*
       * ⚠️ UN ÉCHEC RÉSEAU VAUT « REFUSÉE », PAS « À ACTIVER ». Dans le doute on
       * ne crée rien : activer par erreur envoie l'historique sur nos serveurs
       * sans que personne l'ait demandé, et c'est irréversible.
       */
      return (serrures: <Serrure>[], refusee: true);
    }
  }

  Future<void> _poser(Serrure s) =>
      _api('PUT', '/api/e2ee/coffre', s.enJson());

  /* ══════════════ ACTIVER / OUVRIR ══════════════ */

  /// À la connexion : ouvre l'archive si elle existe, la crée sinon.
  ///
  /// 🔴 LE MOT DE PASSE EST DÉJÀ LÀ — l'utilisateur vient de le taper. C'est le
  /// seul moment du cycle de vie où ce secret existe sans qu'on ait à le
  /// redemander, et c'est ce qui rend la serrure « mot de passe » utile malgré
  /// sa limite.
  ///
  /// ⚠️ IL N'EST GARDÉ NULLE PART. Il traverse cette fonction et en sort.
  ///
  /// ⚠️ NE LÈVE JAMAIS ET NE BLOQUE PAS LA CONNEXION : empêcher quelqu'un
  /// d'entrer parce qu'une sauvegarde a échoué serait bien pire que l'absence
  /// d'historique.
  Future<int> aLaConnexion(String motDePasse) async {
    try {
      final coffre = await lireCoffre();

      if (coffre.serrures.isEmpty) {
        if (coffre.refusee) return 0;
        final a = creerArchive({TypeSerrure.motdepasse: motDePasse});
        for (final s in a.serrures) {
          await _poser(s);
        }
        _maitresse = a.maitresse;
        return 0;
      }

      final mdp = coffre.serrures.where((s) => s.type == 'motdepasse');
      if (mdp.isEmpty) return 0;

      _maitresse = ouvrirArchive(motDePasse, mdp.first);
      return 1;
    } catch (_) {
      /*
       * ⚠️ UN ÉCHEC ICI VEUT DIRE « MAUVAIS MOT DE PASSE », et rien d'autre :
       * AES-GCM authentifie. Le cas arrive quand le mot de passe du COMPTE a
       * changé sans que la serrure suive.
       */
      _maitresse = null;
      return 0;
    }
  }


  /// Crée l'archive protégée par une CLÉ DE RÉCUPÉRATION, et la rend.
  ///
  /// 🔴 C'EST LE SEUL SECRET DE CETTE ARCHIVE tant qu'aucun autre n'est ajouté.
  /// Le mot de passe n'existe qu'à la connexion ; on ne peut donc pas poser sa
  /// serrure ici, et l'appelant DOIT montrer ces douze mots à l'utilisateur.
  ///
  /// ⚠️ SI UNE ARCHIVE EXISTE DÉJÀ, ON N'EN CRÉE PAS UNE SECONDE : on poserait
  /// sinon une archive orpheline, et l'ancienne deviendrait illisible.
  Future<String> activerAvecCleRecuperation() async {
    final coffre = await lireCoffre();
    if (coffre.serrures.isNotEmpty) {
      throw StateError('Une sauvegarde existe déjà sur ce compte.');
    }

    final cle = tirerCleRecuperation();
    final a = creerArchive({TypeSerrure.recuperation: cle});
    for (final s in a.serrures) {
      await _poser(s);
    }
    _maitresse = a.maitresse;
    return cle;
  }

  /// Referme — déconnexion, ou changement de compte.
  void refermer() => _maitresse = null;

  /* ══════════════ DÉPOSER ══════════════ */

  /// Dépose un lot de messages dans l'archive.
  ///
  /// ⚠️ PAR LOTS, PAS PAR MESSAGE. Un bloc par message ferait une requête réseau
  /// par message, et 200 octets de chiffré pour 30 de texte — l'en-tête AES-GCM
  /// et le JSON pèsent plus que la charge.
  Future<bool> deposer(List<Map<String, dynamic>> messages) async {
    final cle = _maitresse;
    if (cle == null || messages.isEmpty) return false;

    try {
      final clair = Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 1, 'messages': messages})),
      );
      final iv = ivNeuf();
      await _api('POST', '/api/e2ee/archive', {
        'iv': base64.encode(iv),
        'contenu': base64.encode(chiffrerAvec(cle, iv, clair)),
        'nbMessages': messages.length,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Relit toute l'archive.
  ///
  /// ⚠️ UN BLOC ILLISIBLE NE BLOQUE PAS LES AUTRES : on le compte et on continue.
  /// Une restauration silencieusement partielle est pire qu'un échec net, donc
  /// le nombre remonte à l'appelant.
  Future<({List<Map<String, dynamic>> messages, int illisibles})> restaurer() async {
    final cle = _maitresse;
    if (cle == null) return (messages: <Map<String, dynamic>>[], illisibles: 0);

    final r = await _api('GET', '/api/e2ee/archive', null);
    final blocs = (r['blocs'] as List? ?? const []).cast<Map<String, dynamic>>();

    final vus = <String, Map<String, dynamic>>{};
    var illisibles = 0;

    for (final b in blocs) {
      try {
        final clair = dechiffrerAvec(
          cle,
          Uint8List.fromList(base64.decode(b['iv'] as String)),
          Uint8List.fromList(base64.decode(b['contenu'] as String)),
        );
        final charge = jsonDecode(utf8.decode(clair)) as Map<String, dynamic>;
        /*
         * ⚠️ LA VERSION SE VÉRIFIE ET ON S'ARRÊTE SI ELLE EST INCONNUE. Un
         * client ancien rendrait sinon des messages tronqués sans le dire.
         */
        if (charge['v'] != 1) {
          illisibles++;
          continue;
        }
        for (final m in (charge['messages'] as List).cast<Map<String, dynamic>>()) {
          // Du plus ancien au plus récent : une correction déposée plus tard
          // l'emporte sur la version d'origine.
          vus[m['id'] as String] = m;
        }
      } catch (_) {
        illisibles++;
      }
    }
    return (messages: vus.values.toList(), illisibles: illisibles);
  }

  /// Supprime tout — blocs ET serrures — et mémorise le refus.
  Future<void> toutEffacer() async {
    await _api('DELETE', '/api/e2ee/archive', null);
    refermer();
  }
}
