import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/media_cache.dart';
import 'e2ee_media.dart';

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

  /// Établissement de la requête — même ordre que `ApiClient.delaiReponse`.
  ///
  /// 🔴 SANS CE DÉLAI, UN GET QUI NE REVIENT PAS LAISSE LE SPINNER TOURNER
  /// POUR TOUJOURS : `package:http` n'a aucun timeout, le `catch` de la bulle
  /// ne s'exécute jamais, et `_enCours` empêche de réessayer.
  static const delaiDebut = Duration(seconds: 30);

  /// Sans octet pendant ce temps : la connexion est morte (redirect qui ne
  /// finit pas, keep-alive vide). Un téléchargement LENT continue — le chrono
  /// repart à chaque chunk.
  static const delaiInactivite = Duration(seconds: 30);

  static const _delaiCache = Duration(seconds: 5);
  static const _delaiDechiffrage = Duration(minutes: 2);

  /// Le fichier en clair, prêt à afficher. Lève [FichierInvalide] si le
  /// fichier reçu n'est pas celui annoncé, [MediaIndisponible] si le serveur ne
  /// l'a plus — ou si la requête n'a pas abouti à temps (statut 408).
  static Future<File> ouvrir(
    DescripteurMedia d, {
    required String baseUrl,
    required String? token,
  }) {
    final deja = _enCours[d.id];
    if (deja != null) return deja;
    final f = _ouvrir(
      d,
      baseUrl,
      token,
    ).whenComplete(() => _enCours.remove(d.id));
    _enCours[d.id] = f;
    return f;
  }

  /// Range le clair d'un média qu'on vient d'ENVOYER : l'expéditeur l'a
  /// déjà, le retélécharger pour le déchiffrer serait absurde.
  static Future<void> garderClair(DescripteurMedia d, List<int> clair) async {
    try {
      await MediaCache.put(_cle(d), _extension(d), clair).timeout(_delaiCache);
    } catch (_) {}
  }

  /// Les octets CHIFFRÉS du serveur, authentifiés comme un média en clair.
  ///
  /// ⚠️ JETON OBLIGATOIRE. Un GET sans `Authorization` est le chemin qui
  /// ouvrait une redirection de login jamais close, spinner infini, alors que
  /// le même fichier s'affichait dans le navigateur.
  static Future<Uint8List> telechargerOctets({
    required String baseUrl,
    required String id,
    required String token,
  }) async {
    final adr = adresseTelechargementMedia(
      baseUrl: baseUrl,
      id: id,
      token: token,
    );
    final client = http.Client();
    try {
      final req = http.Request('GET', adr.uri)..headers.addAll(adr.headers);
      final resp = await client.send(req).timeout(delaiDebut);
      if (resp.statusCode != 200) throw MediaIndisponible(resp.statusCode);
      final out = BytesBuilder(copy: false);
      await for (final chunk in resp.stream.timeout(delaiInactivite)) {
        out.add(chunk);
      }
      return out.takeBytes();
    } on TimeoutException {
      throw const MediaIndisponible(408);
    } finally {
      client.close();
    }
  }

  static String _cle(DescripteurMedia d) => 'e2ee_${d.id}';

  static String _extension(DescripteurMedia d) {
    final nom = d.nom ?? '';
    final point = nom.lastIndexOf('.');
    if (point > 0 && point < nom.length - 1) {
      return nom.substring(point + 1).toLowerCase();
    }
    final sous = d.mime.split('/').last.split(';').first;
    return sous.isEmpty ? 'bin' : sous;
  }

  static Future<File> _ouvrir(
    DescripteurMedia d,
    String baseUrl,
    String? token,
  ) async {
    try {
      final garde = await MediaCache.get(
        _cle(d),
        _extension(d),
      ).timeout(_delaiCache);
      if (garde != null) return File(garde);
    } catch (_) {
      // Cache muet ou lent : on passe au réseau plutôt que de tourner à vide.
    }

    final jeton = token;
    if (jeton == null || jeton.isEmpty) {
      throw const MediaIndisponible(401);
    }

    final chiffre = await telechargerOctets(
      baseUrl: baseUrl,
      id: d.id,
      token: jeton,
    );

    final cle = d.cle;
    final empreinte = d.empreinte;
    final taille = d.taille;
    final clair = await Isolate.run<Uint8List>(
      () => dechiffrerFichier(
        chiffre,
        cle: cle,
        empreinte: empreinte,
        taille: taille,
      ),
    ).timeout(_delaiDechiffrage);

    return File(await _rangerClair(d, clair));
  }

  static Future<String> _rangerClair(
    DescripteurMedia d,
    List<int> clair,
  ) async {
    try {
      return await MediaCache.put(
        _cle(d),
        _extension(d),
        clair,
      ).timeout(_delaiCache);
    } catch (_) {
      final tmp = File(
        '${Directory.systemTemp.path}/${_cle(d)}.${_extension(d)}',
      );
      await tmp.writeAsBytes(clair, flush: true);
      return tmp.path;
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
