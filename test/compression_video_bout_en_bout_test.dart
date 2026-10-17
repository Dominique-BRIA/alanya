// LA CHAÎNE VIDÉO MOBILE, MONTÉE ENTIÈRE.
//
// 🔴 POURQUOI CE BANC EXISTE. Les bancs de `compression_video_test.dart`
// éprouvent la DÉCISION (`consignePour`, les paliers, le seuil) et ils sont
// verts depuis le début. Pourtant le user a dû revenir trois fois sur la
// compression mobile : « depuis, tu me dis que tu as fait alors que tu n'as pas
// fait » (16/10/2026). La raison est structurelle — tester la décision ne dit
// RIEN de ce qui l'entoure : la lecture des dimensions, la consigne réellement
// passée au code natif, la relecture du fichier produit, et les champs rendus à
// l'écran d'envoi.
//
// 🐛 CE BANC A ATTRAPÉ SON PREMIER DÉFAUT LE JOUR MÊME : `definitionAutreNiveau`
// n'était renseigné que par les chemins de REFUS, pas par celui du succès — le
// seul que l'utilisateur voit.
//
// ⚠️ LES DEUX CANAUX SONT SIMULÉS, et c'est tout l'intérêt : on vérifie ce que
// le Dart DEMANDE au code natif (dimensions et débit), ce qu'il fait de ce
// qu'on lui rend, et ce qu'il ne demande pas quand il ne faut rien faire.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/core/compression_image.dart' show NiveauQualite;
import 'package:alanya/core/compression_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canalInfo = MethodChannel('video_compress');
  const canalNotre = MethodChannel('alanya/compression_video');
  final messager =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory bac;
  late File source;
  /// Les arguments reçus par le code natif, pour les éprouver.
  Map<Object?, Object?>? consigneRecue;
  /// Le nombre d'octets que le faux transcodeur rendra.
  var octetsRendus = 0;

  setUp(() async {
    bac = await Directory.systemTemp.createTemp('alanya_compression');
    source = File('${bac.path}/source.mp4')..writeAsBytesSync(List.filled(64, 7));
    consigneRecue = null;
    octetsRendus = 0;
  });

  tearDown(() async {
    messager.setMockMethodCallHandler(canalInfo, null);
    messager.setMockMethodCallHandler(canalNotre, null);
    if (bac.existsSync()) await bac.delete(recursive: true);
  });

  /// Installe les deux faux canaux. [largeur] × [hauteur] et [dureeMs]
  /// décrivent la vidéo d'entrée ; [poidsSortie] ce que rendra le transcodeur.
  void simuler({
    required int largeur,
    required int hauteur,
    required int dureeMs,
    required int poidsSortie,
    bool transcodeurMuet = false,
  }) {
    messager.setMockMethodCallHandler(canalInfo, (appel) async {
      if (appel.method != 'getMediaInfo') return null;
      // Le greffon rend une CHAÎNE JSON, pas une table : s'en écarter ferait
      // passer le banc là où l'application échouerait.
      return json.encode({
        'path': source.path,
        'width': largeur,
        'height': hauteur,
        'duration': dureeMs,
        'filesize': 0,
      });
    });
    messager.setMockMethodCallHandler(canalNotre, (appel) async {
      if (appel.method != 'compresser') return null;
      consigneRecue = appel.arguments as Map<Object?, Object?>;
      if (transcodeurMuet) return null;
      final produit = File('${bac.path}/produit.mp4')
        ..writeAsBytesSync(List.filled(poidsSortie, 3));
      octetsRendus = poidsSortie;
      return produit.path;
    });
  }

  /// Une vidéo d'entrée de [octets] octets.
  Uint8List entree(int octets) => Uint8List.fromList(List.filled(octets, 9));

  Future<ResultatCompressionVideo> lancer(
    Uint8List original, {
    NiveauQualite niveau = NiveauQualite.normal,
  }) =>
      compresserVideo(
        original,
        chemin: source.path,
        nomFichier: 'tournage.mov',
        mimeType: 'video/mp4',
        niveau: niveau,
      );

  test('du 1080p lourd : la consigne part, le produit revient, tout est dit',
      () async {
    // 30 s à 8 Mbit/s = 30 Mo. Le palier 720p doit sortir ~4,5 Mo.
    final original = entree(30 * 1000 * 1000);
    simuler(
        largeur: 1920,
        hauteur: 1080,
        dureeMs: 30000,
        poidsSortie: 4 * 1000 * 1000);

    final r = await lancer(original);

    // 1. Ce qu'on a DEMANDÉ au code natif.
    expect(consigneRecue, isNotNull, reason: 'le transcodeur doit être appelé');
    expect(consigneRecue!['bordCourt'], 720);
    expect(consigneRecue!['bordLong'], 1280);
    expect(consigneRecue!['debit'], debitPalier[720],
        reason: 'le débit du palier, celui que video_compress ne savait pas '
            'transmettre — toute la raison du module natif');

    // 2. Ce qu'on a fait de la réponse.
    expect(r.compresse, isTrue);
    expect(r.octets.length, octetsRendus);
    expect(r.tailleAvant, original.length);
    expect(r.tailleApres, octetsRendus);
    expect(r.nomFichier, 'tournage.mp4',
        reason: 'le nom suit les octets : le natif rend toujours du MP4');
    expect(r.mimeType, 'video/mp4');

    // 3. Ce que l'écran d'envoi recevra.
    /*
     * ⚠️ PAS DE BOUTON POUR UNE SOURCE AU-DESSUS DE 720p, depuis que le niveau
     * haut plafonne lui aussi à 720 (17/10/2026) : les deux niveaux rendent
     * exactement la même chose, et un bouton qui ne change rien ne doit pas
     * paraître.
     */
    expect(r.niveauSuperieurPossible, isFalse,
        reason: 'les deux niveaux donnent 720p : rien à proposer');
    expect(r.definitionAutreNiveau, 720,
        reason: '🐛 ce champ ne voyageait que par les chemins de refus');
  });

  test('une vidéo filmée en 720p : le bouton existe et annonce 720p', () async {
    // 20 s à 5 Mbit/s = 12,5 Mo, bien au-dessus du seuil.
    simuler(
        largeur: 1280,
        hauteur: 720,
        dureeMs: 20000,
        poidsSortie: 2 * 1000 * 1000);

    final r = await lancer(entree(12500000));

    expect(consigneRecue!['bordCourt'], 360, reason: 'une marche en dessous');
    expect(r.compresse, isTrue);
    expect(r.niveauSuperieurPossible, isTrue,
        reason: 'le défaut signalé par le professeur : le bouton manquait');
    expect(r.definitionAutreNiveau, 720,
        reason: 'et il doit annoncer 720p, pas 1080p — on n\'agrandit jamais');
  });

  test('déjà légère : LE NATIF N\'EST MÊME PAS APPELÉ', () async {
    // 60 s à 1 Mbit/s = 7,5 Mo : sous le seuil du 16/10.
    final original = entree(7500000);
    simuler(
        largeur: 1280, hauteur: 720, dureeMs: 60000, poidsSortie: 1000000);

    final r = await lancer(original);

    expect(consigneRecue, isNull,
        reason: 'faire tourner l\'encodeur pour rien coûte la batterie et le '
            'temps que le user trouve déjà trop long');
    expect(r.compresse, isFalse);
    expect(r.raisonSaut, RaisonSautVideo.dejaPetite);
    expect(r.octets, same(original), reason: 'les octets d\'origine, intacts');
    expect(r.niveauSuperieurPossible, isFalse,
        reason: 'rien n\'a été fait : le bouton serait une promesse sans suite');
  });

  test('le transcodeur renonce : la vidéo part entière, l\'envoi ne casse pas',
      () async {
    final original = entree(30000000);
    simuler(
        largeur: 1920,
        hauteur: 1080,
        dureeMs: 30000,
        poidsSortie: 0,
        transcodeurMuet: true);

    final r = await lancer(original);

    expect(r.compresse, isFalse);
    expect(r.raisonSaut, RaisonSautVideo.transcodageImpossible);
    expect(r.octets, same(original));
  });

  test('un produit aussi lourd que la source est jeté', () async {
    final original = entree(10000000);
    // 9,9 Mo pour 10 Mo : sous les 10 % de gain minimum.
    simuler(
        largeur: 1920, hauteur: 1080, dureeMs: 10000, poidsSortie: 9900000);

    final r = await lancer(original);

    expect(r.compresse, isFalse);
    expect(r.raisonSaut, RaisonSautVideo.sansGain);
    expect(r.octets, same(original));
  });

  test('dimensions illisibles : on n\'appelle pas le natif à l\'aveugle',
      () async {
    messager.setMockMethodCallHandler(canalInfo, (_) async => throw 'illisible');
    messager.setMockMethodCallHandler(canalNotre, (appel) async {
      consigneRecue = appel.arguments as Map<Object?, Object?>;
      return null;
    });

    final original = entree(30000000);
    final r = await lancer(original);

    expect(consigneRecue, isNull);
    expect(r.compresse, isFalse);
    expect(r.raisonSaut, RaisonSautVideo.dimensionsInconnues);
  });

  test('le fichier produit ne reste pas dans le cache', () async {
    simuler(
        largeur: 1920, hauteur: 1080, dureeMs: 30000, poidsSortie: 4000000);
    await lancer(entree(30000000));
    expect(File('${bac.path}/produit.mp4').existsSync(), isFalse,
        reason: 'une vidéo pèse des mégaoctets : on ne les garde pas');
  });
}
