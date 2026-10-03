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

  /// Le fichier en clair, prêt à afficher. Lève [FichierInvalide] si le
  /// fichier reçu n'est pas celui annoncé, [MediaIndisponible] si le serveur ne
  /// l'a plus.
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
  ) async {
    final garde = await MediaCache.get(_cle(d), _extension(d));
    if (garde != null) return File(garde);

    final rep = await http.get(
      Uri.parse(
        '$baseUrl/api/media/${d.id}${token != null ? '?token=$token' : ''}',
      ),
    );
    if (rep.statusCode != 200) throw MediaIndisponible(rep.statusCode);
    final chiffre = rep.bodyBytes;

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
    );

    return File(await MediaCache.put(_cle(d), _extension(d), clair));
  }
}

/// Le serveur n'a plus ce fichier, ou nous le refuse.
class MediaIndisponible implements Exception {
  const MediaIndisponible(this.statut);
  final int statut;
  @override
  String toString() => 'MediaIndisponible($statut)';
}
