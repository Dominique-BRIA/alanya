import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/media_cache.dart';
import 'e2ee_media.dart';

/// Donne le jeton d'accès À JOUR ; [renouveler] le fait rafraîchir après un
/// 401. Voir `AuthedApi.jeton`.
typedef FournisseurJeton = Future<String?> Function({bool renouveler});

/// OUVRIR UN MÉDIA CHIFFRÉ — le télécharger, le vérifier, le déchiffrer.
///
/// Jumeau de `STAGE-WEB/src/services/e2ee-media-ouverture.ts` (cours,
/// chapitre 23). Le fichier du serveur est illisible ; le descripteur reçu dans
/// l'enveloppe en donne la clé et l'empreinte.
///
/// ⚠️ LE CLAIR EST GARDÉ dans le cache des médias de l'application, comme le
/// texte déchiffré l'est dans le cache des messages : c'est la règle décidée
/// (le stockage local en clair est VOULU). Une photo ouverte ne se
/// retélécharge plus.
///
/// ⚠️ LE DÉCHIFFREMENT TOURNE DANS UN ISOLAT : AES-GCM en Dart pur sur une
/// vidéo de 50 Mo prend plusieurs secondes, qui figeraient l'écran.
class OuvertureMediaChiffre {
  OuvertureMediaChiffre._();

  static final _enCours = <String, Future<File>>{};

  /// Le fichier en clair, prêt à afficher. Lève [FichierInvalide] si le
  /// fichier reçu n'est pas celui annoncé, [MediaIndisponible] si le serveur ne
  /// l'a plus.
  static Future<File> ouvrir(
    DescripteurMedia d, {
    required String baseUrl,
    required String? token,
    FournisseurJeton? jeton,
  }) {
    final deja = _enCours[d.id];
    if (deja != null) return deja;
    /*
     * 🔴 LE CHARGEMENT QUI TOURNAIT SANS FIN SUR LE TÉLÉPHONE (03/10/2026).
     *
     * 🐛 C'ÉTAIT `.whenComplete(() => _enCours.remove(d.id))`. La flèche
     * RENVOIE ce que `remove` rend : la valeur retirée, c'est-à-dire CE
     * Future-ci. Or `whenComplete` ATTEND tout Future que son rappel renvoie.
     * Le Future s'attendait donc lui-même : il ne se terminait jamais, ni en
     * succès ni en erreur — même quand le fichier était déjà en cache. Toute
     * photo chiffrée restait sur son aperçu flou, chargement compris, et un
     * toucher réattendait le même Future mort.
     *
     * ⚠️ UN CORPS EN ACCOLADES, qui ne renvoie rien. Trouvé par
     * `test/e2ee_media_ouverture_test.dart` : le banc d'interopérabilité
     * déchiffrait sans passer par `ouvrir`, il ne pouvait pas le voir.
     */
    final f = _ouvrir(d, baseUrl, token, jeton).whenComplete(() {
      _enCours.remove(d.id);
    });
    _enCours[d.id] = f;
    return f;
  }

  /// Range le clair d'un média qu'on vient d'ENVOYER : l'expéditeur l'a
  /// déjà, le retélécharger pour le déchiffrer serait absurde.
  static Future<void> garderClair(DescripteurMedia d, List<int> clair) async {
    try {
      await MediaCache.put(_cle(d), _extension(d), clair);
    } catch (_) {}
  }

  static String _cle(DescripteurMedia d) => 'e2ee_${d.id}';

  static String _extension(DescripteurMedia d) {
    final nom = d.nom ?? '';
    final point = nom.lastIndexOf('.');
    if (point > 0 && point < nom.length - 1)
      return nom.substring(point + 1).toLowerCase();
    final sous = d.mime.split('/').last.split(';').first;
    return sous.isEmpty ? 'bin' : sous;
  }

  static Future<File> _ouvrir(
    DescripteurMedia d,
    String baseUrl,
    String? token,
    FournisseurJeton? jeton,
  ) async {
    final garde = await MediaCache.get(_cle(d), _extension(d));
    if (garde != null) return File(garde);

    final chiffre = await _telecharger(
      Uri.parse('$baseUrl/api/media/${d.id}'),
      token,
      jeton,
    );

    final clair = await dechiffrerHorsDuFil(
      chiffre,
      cle: d.cle,
      empreinte: d.empreinte,
      taille: d.taille,
    );

    return File(await MediaCache.put(_cle(d), _extension(d), clair));
  }

  /// Au-delà, sans un octet reçu, le téléchargement est abandonné.
  ///
  /// ⚠️ UN DÉLAI D'INACTIVITÉ, PAS UN DÉLAI TOTAL : une vidéo de 50 Mo sur un
  /// réseau mobile lent peut prendre plusieurs minutes, et c'est normal. Ce
  /// qui ne l'est pas, c'est une connexion qui ne renvoie plus rien.
  /// Modifiable pour les tests.
  static Duration delaiInactivite = const Duration(seconds: 30);

  /// Télécharge le fichier chiffré, comme `CachedMedia` télécharge les autres.
  ///
  /// ⚠️ C'ÉTAIT UN `http.get` NU : aucun délai, aucune nouvelle tentative, et
  /// le jeton dans l'adresse plutôt qu'en en-tête comme partout ailleurs dans
  /// l'application. Ce n'était PAS la cause du chargement sans fin (voir
  /// `ouvrir`), mais le même symptôme aurait suivi : une connexion qui se
  /// bloque — réseau mobile qui décroche, stockage qui ne répond plus — ne
  /// finissait jamais. Avec le délai, elle finit en « échec », et un toucher
  /// relance.
  ///
  /// ⚠️ VÉRIFIÉ, ET ÉCARTÉ : un jeton invalide ne bloque pas. Le serveur
  /// répond en moins d'une seconde (401 sans jeton, 400 avec un faux).
  ///
  /// 🔴 LE JETON EST DEMANDÉ AU MOMENT DU TÉLÉCHARGEMENT, pas reçu de l'écran.
  ///
  /// 🐛 « A envoie un média à B : impossible de télécharger, il faut rouvrir
  /// la conversation » (user, 03/10/2026). L'écran passait le jeton lu à son
  /// ouverture ; expiré entre-temps (15 min), le serveur répondait 401. Avec
  /// [jeton], on lit le jeton du stockage — que le reste de l'application tient
  /// à jour — et, sur un 401, on le fait rafraîchir UNE fois avant de
  /// réessayer. [token] ne sert plus que de repli, sans fournisseur.
  static Future<Uint8List> _telecharger(
    Uri adresse,
    String? token,
    FournisseurJeton? jeton,
  ) async {
    var courant = jeton != null ? await jeton() : token;
    var renouvele = false;
    var essai = 0;
    while (true) {
      final client = http.Client();
      try {
        final rep = await client
            .send(http.Request('GET', adresse)
              ..headers.addAll({
                if (courant != null && courant.isNotEmpty)
                  'Authorization': 'Bearer $courant',
              }))
            .timeout(delaiInactivite);
        // Jeton expiré : on le renouvelle une fois, et on rejoue.
        if (rep.statusCode == 401 && jeton != null && !renouvele) {
          renouvele = true;
          courant = await jeton(renouveler: true);
          if (courant != null) continue;
        }
        // Un refus du serveur ne se répare pas en réessayant.
        if (rep.statusCode != 200) throw MediaIndisponible(rep.statusCode);
        final octets = BytesBuilder(copy: false);
        await for (final morceau in rep.stream.timeout(delaiInactivite)) {
          octets.add(morceau);
        }
        return octets.takeBytes();
      } on MediaIndisponible {
        rethrow;
      } catch (_) {
        if (essai < 2) {
          essai++;
          await Future.delayed(Duration(milliseconds: 400 * essai));
          continue;
        }
        rethrow;
      } finally {
        // Fermer le client coupe aussi une connexion restée pendante.
        client.close();
      }
    }
  }
}

/// Le serveur n'a plus ce fichier, ou nous le refuse.
class MediaIndisponible implements Exception {
  const MediaIndisponible(this.statut);
  final int statut;
  @override
  String toString() => 'MediaIndisponible($statut)';
}
