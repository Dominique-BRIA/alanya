import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'e2ee_media.dart';

/// CHIFFRER UN MÉDIA DE FICHIER À FICHIER — envoi en morceaux, lot 2 (cours,
/// chapitre 43).
///
/// 🔴 POURQUOI. [chiffrerFichier] tient tout en mémoire : le clair, puis le
/// chiffré, puis la requête qui le recopie. Une vidéo de 250 Mo, c'est trois
/// quarts de gigaoctet — assez pour faire tuer l'application. Et l'envoi en
/// morceaux a besoin du chiffré SUR DISQUE : Android l'enverra par tranches,
/// application fermée, longtemps après que cette mémoire a disparu.
///
/// ⚠️ MÊME FORMAT, MÊMES OCTETS. Le format AGB1 chiffre chaque bloc de 64 Kio
/// séparément, avec un nonce DÉTERMINÉ par son numéro et la marque « dernier ».
/// Chiffrer bloc par bloc donne donc, à clé égale, exactement les octets de
/// [chiffrerFichier] : le destinataire — web ou mobile — n'a rien à changer, et
/// le test le prouve octet pour octet.
///
/// ⚠️ L'EMPREINTE SE CALCULE AU FIL DE L'EAU, sur le chiffré qu'on écrit :
/// relire le fichier ensuite doublerait les lectures.
class FichierChiffreSurDisque {
  const FichierChiffreSurDisque({
    required this.chemin,
    required this.taille,
    required this.tailleClair,
    required this.cle,
    required this.empreinte,
  });

  /// Où le chiffré a été écrit.
  final String chemin;

  /// Taille du CHIFFRÉ — celle qu'on annonce au serveur.
  final int taille;

  /// Taille du clair — celle du descripteur.
  final int tailleClair;

  /// Clé, base64 (comme [FichierChiffre.cle]).
  final String cle;

  /// SHA-256 du chiffré, 32 octets.
  final Uint8List empreinte;

  /// Pour le descripteur chiffré (base64, comme [FichierChiffre.empreinte]).
  String get empreinteBase64 => base64Encode(empreinte);

  /// Pour le serveur, qui vérifie l'assemblage (hexadécimal).
  String get empreinteHex =>
      empreinte.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
}

/// Chiffre vers [destination], depuis le fichier [source] OU les [octets]
/// (un vocal qui n'existe qu'en mémoire). SYNCHRONE : à n'appeler que dans un
/// isolat — voir [chiffrerVersFichierHorsDuFil].
///
/// [cleImposee] n'existe que pour le test : une clé réutilisée pour un autre
/// contenu casserait tout.
FichierChiffreSurDisque chiffrerVersFichier({
  required String destination,
  String? source,
  Uint8List? octets,
  Uint8List? cleImposee,
}) {
  if ((source == null) == (octets == null)) {
    throw ArgumentError('une source : un chemin OU des octets');
  }
  final cle = cleImposee ??
      Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
  final entree = source == null ? null : File(source).openSync();
  final sortieFichier = File(destination);
  sortieFichier.parent.createSync(recursive: true);
  final sortie = sortieFichier.openSync(mode: FileMode.write);
  final sha = SHA256Digest();
  var taille = 0;
  var reussi = false;
  try {
    final tailleClair = entree?.lengthSync() ?? octets!.length;
    // Un fichier vide fait UN bloc (vide), comme dans [chiffrerFichier].
    final nbBlocs = max(1, (tailleClair + tailleBloc - 1) ~/ tailleBloc);
    final tampon = Uint8List(tailleBloc);
    for (var i = 0; i < nbBlocs; i++) {
      final debut = i * tailleBloc;
      final n = min(tailleBloc, tailleClair - debut);
      final Uint8List bloc;
      if (entree != null) {
        // Une lecture peut rendre moins que demandé : on insiste jusqu'au
        // bloc entier. Un fichier qui raccourcit pendant qu'on le lit est
        // une erreur, pas un fichier plus petit.
        var lus = 0;
        while (lus < n) {
          final k = entree.readIntoSync(tampon, lus, n);
          if (k == 0) {
            throw const FileSystemException('le fichier a changé pendant le chiffrement');
          }
          lus += k;
        }
        bloc = Uint8List.sublistView(tampon, 0, n);
      } else {
        bloc = Uint8List.sublistView(octets!, debut, debut + n);
      }
      final chiffre = chiffrerBlocAgb1(cle, i, i == nbBlocs - 1, bloc);
      sortie.writeFromSync(chiffre);
      sha.update(chiffre, 0, chiffre.length);
      taille += chiffre.length;
    }
    final empreinte = Uint8List(32);
    sha.doFinal(empreinte, 0);
    reussi = true;
    return FichierChiffreSurDisque(
      chemin: destination,
      taille: taille,
      tailleClair: tailleClair,
      cle: base64Encode(cle),
      empreinte: empreinte,
    );
  } finally {
    sortie.closeSync();
    entree?.closeSync();
    // Un chiffré à moitié écrit ne doit jamais partir : on l'efface.
    if (!reussi && sortieFichier.existsSync()) sortieFichier.deleteSync();
  }
}

/// [chiffrerVersFichier] dans un isolat.
///
/// 🔴 TOUJOURS PAR ICI, JAMAIS PAR UN `Isolate.run` ÉCRIT SUR PLACE (cours,
/// chapitre 27) : une fermeture emporte tout le contexte de la fonction qui
/// l'a créée. Ici, le seul contexte est celui des paramètres.
Future<FichierChiffreSurDisque> chiffrerVersFichierHorsDuFil({
  required String destination,
  String? source,
  Uint8List? octets,
}) =>
    Isolate.run(
      () => chiffrerVersFichier(destination: destination, source: source, octets: octets),
    );
