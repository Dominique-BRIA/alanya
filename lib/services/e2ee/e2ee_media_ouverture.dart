import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// L'avancement d'une ouverture en cours, de 0 à 1 ; `null` pendant le
  /// déchiffrement d'un fichier dont on ne sait pas encore le poids.
  ///
  /// 🐛 « ÇA TOURNE, SANS POURCENTAGE, ET ÇA S'ARRÊTE QUAND ON SORT DE LA
  /// CONVERSATION » (user, 27/10/2026). Le téléchargement continuait, mais la
  /// bulle recréée au retour ne le savait pas. Tenu ICI, hors de la bulle, il
  /// se retrouve par l'identifiant du média.
  static final _avancements = <String, ValueNotifier<double?>>{};

  /// Une ouverture de ce média est-elle en cours ?
  static bool enCours(String mediaId) => _enCours.containsKey(mediaId);

  /// L'avancement de l'ouverture en cours de ce média, s'il y en a une.
  static ValueListenable<double?>? avancement(String mediaId) =>
      _avancements[mediaId];

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
    final avance = _avancements[d.id] = ValueNotifier<double?>(0);
    final f = _ouvrir(d, baseUrl, token, jeton, avance).whenComplete(() {
      _enCours.remove(d.id);
      _avancements.remove(d.id);
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

  /// [garderClair] pour un document resté sur le disque : une copie de fichier.
  static Future<void> garderClairFichier(DescripteurMedia d, String chemin) async {
    try {
      await MediaCache.putFichier(_cle(d), _extension(d), chemin);
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

  /*
   * 🔴 SUR LE DISQUE DE BOUT EN BOUT (27/10/2026, comme WhatsApp). Le chiffré
   * était reçu EN MÉMOIRE, déchiffré en mémoire — une seconde copie — puis
   * écrit : un gros document reçu ne s'ouvrait jamais. Désormais le chiffré
   * s'écrit en flux dans `.part`, se déchiffre de fichier à fichier vers
   * `.dec`, et ne prend son nom définitif qu'entier et vérifié : un fichier à
   * moitié écrit ne passe jamais pour le média.
   */
  static Future<File> _ouvrir(
    DescripteurMedia d,
    String baseUrl,
    String? token,
    FournisseurJeton? jeton,
    ValueNotifier<double?> avance,
  ) async {
    final garde = await MediaCache.get(_cle(d), _extension(d));
    if (garde != null) return File(garde);

    final cible = await MediaCache.chemin(_cle(d), _extension(d));
    final partiel = File('$cible.part');
    final dechiffre = File('$cible.dec');
    try {
      await _telecharger(
        Uri.parse('$baseUrl/api/media/${d.id}'),
        token,
        jeton,
        partiel,
        // Le chiffré pèse le clair plus 16 octets par bloc de 64 Kio.
        (recus, total) {
          final t = total ?? d.taille + (d.taille ~/ tailleBloc + 1) * 16;
          if (t > 0) avance.value = (recus / t).clamp(0.0, 1.0);
        },
      );
      avance.value = null;
      await dechiffrerFichierHorsDuFil(
        source: partiel.path,
        destination: dechiffre.path,
        cle: d.cle,
        empreinte: d.empreinte,
        taille: d.taille,
      );
      return await dechiffre.rename(cible);
    } finally {
      if (await partiel.exists()) await partiel.delete();
      if (await dechiffre.exists()) await dechiffre.delete();
    }
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
  static Future<void> _telecharger(
    Uri adresse,
    String? token,
    FournisseurJeton? jeton,
    File cible,
    void Function(int recus, int? total) onRecu,
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
        // En flux vers le disque : un morceau à la fois en mémoire.
        final sortie = cible.openWrite();
        var recus = 0;
        try {
          await for (final morceau in rep.stream.timeout(delaiInactivite)) {
            sortie.add(morceau);
            recus += morceau.length;
            onRecu(recus, rep.contentLength);
          }
        } finally {
          await sortie.close();
        }
        return;
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
