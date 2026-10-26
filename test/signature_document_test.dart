import 'dart:io';
import 'dart:math';

import 'package:alanya/core/signature_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// La copie signée d'un document sensible (22/10/2026) : ce qui est écrit aux
/// bords et dans les métadonnées, et la règle « le geste n'est jamais refusé ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SignatureSortie signature({String? expediteur}) => SignatureSortie(
    geste: GesteSortie.partage,
    alanyaId: '67641599',
    appareil: 'samsung SM-A515F',
    quand: DateTime(2026, 10, 22, 9, 5, 7),
    code: '3f9a0c1e5b7d2a4c6e8f0a1b2c3d4e5f',
    expediteurId: expediteur,
    mediaId: 'm-42',
  );

  test('le texte des bords : application, ID formaté, appareil, date, code', () {
    expect(
      signature().texteBords,
      'Alanya Work · Alanya 67 64 15 99 · samsung SM-A515F · 22/10/2026 09:05 · '
      '3F9A 0C1E 5B7D 2A4C 6E8F 0A1B 2C3D 4E5F',
    );
  });

  test('photos et vidéos : un champ par bord (recommandation du 25/10/2026)', () {
    expect(signature().bordsVisuels.split('\n'), [
      'Alanya Work · AW 6764 1599',
      '22/10/2026 09:05',
      'samsung SM-A515F',
      '3F9A 0C1E 5B7D 2A4C 6E8F 0A1B 2C3D 4E5F',
    ]);
  });

  test("PDF : l'empreinte à la place de l'Alanya ID (25/10/2026)", () {
    final t = signature().texteBordsPdf;
    expect(t, contains('3F9A 0C1E'));
    expect(t, isNot(contains('67 64 15 99')));
    expect(t, isNot(contains('6764')));
  });

  // Les noms sont écrits en toutes lettres : ce sont ceux que lit une
  // personne dans les propriétés du fichier (demande du user, 24/10/2026).
  test('les métadonnées, sous leurs noms courts', () {
    final m = signature(expediteur: '0000').metadonnees;
    expect(m.keys, [
      'Application',
      'Alanya ID',
      'Appareil',
      'Date Creation',
      'Empreinte numerique',
      'Geste',
      'Expediteur',
      'Document',
    ]);
    expect(m['Application'], 'Alanya Work');
    expect(m['Alanya ID'], '67 64 15 99');
    expect(m['Appareil'], 'samsung SM-A515F');
    expect(m['Date Creation'], startsWith('2026-10-22T09:05:07'));
    expect(m['Date Creation'], matches(RegExp(r'[+-]\d\d:\d\d$')));
    expect(m['Empreinte numerique'], '3f9a0c1e5b7d2a4c6e8f0a1b2c3d4e5f');
    expect(m['Geste'], 'PARTAGE');
    expect(m['Expediteur'], '00 00');
    expect(m['Document'], 'm-42');
    expect(signature().metadonnees.containsKey('Expediteur'), isFalse);
  });

  test('la vidéo reçoit les mêmes informations, sous les mêmes noms', () {
    final e = signature().elementsMp4;
    // Les huit champs en toutes lettres dans le commentaire, que Windows
    // affiche (onglet « Détails »), comme le commentaire EXIF d'une image.
    final commentaire = e.standard['©cmt']!;
    for (final c in signature().metadonnees.entries) {
      expect(commentaire, contains('${c.key}=${c.value}'));
    }
    expect(e.standard['©nam'], signature().texteBords);
    expect(e.standard['cprt'], 'Alanya Work');
    expect(e.standard['©ART'], 'Alanya 67 64 15 99');
    expect(e.libres, signature().metadonnees);
  });

  test('un code neuf : 32 caractères hexadécimaux, jamais le même', () {
    final codes = {for (var i = 0; i < 200; i++) SignatureSortie.nouveauCode()};
    expect(codes, hasLength(200));
    for (final c in codes) {
      expect(c, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
    expect(
      SignatureSortie.nouveauCode(Random(1)),
      SignatureSortie.nouveauCode(Random(1)),
    );
  });

  test('ce que chaque type reçoit', () {
    expect(natureSignature('application/pdf', 'x'), NatureSignature.pdf);
    expect(
      natureSignature('application/octet-stream', 'Contrat.PDF'),
      NatureSignature.pdf,
    );
    expect(natureSignature('image/jpeg', 'a.jpg'), NatureSignature.image);
    expect(natureSignature('image/heic', 'a.heic'), NatureSignature.image);
    expect(natureSignature('image/gif', 'a.gif'), NatureSignature.aucune);
    expect(natureSignature('image/svg+xml', 'a.svg'), NatureSignature.aucune);
    expect(natureSignature('video/mp4', 'a.mp4'), NatureSignature.video);
    // L'audio (25/10/2026) : un M4A est un MP4, mais il n'est pas réencodé.
    expect(natureSignature('audio/mpeg', 'a.mp3'), NatureSignature.audio);
    expect(natureSignature('audio/mp4', 'voix.m4a'), NatureSignature.audio);
    expect(natureSignature('application/octet-stream', 'son.wav'), NatureSignature.audio);
    expect(natureSignature('video/quicktime', 'a.mov'), NatureSignature.video);
    // Incrustable sur Android (réencodée en MP4), sans métadonnées sinon.
    expect(natureSignature('video/webm', 'a.webm'), NatureSignature.video);
    expect(
      natureSignature('application/octet-stream', 'a.webm'),
      NatureSignature.aucune,
    );
    expect(
      natureSignature(
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'a.docx',
      ),
      NatureSignature.aucune,
    );
  });

  group('signer', () {
    late Directory dossier;
    setUp(() => dossier = Directory.systemTemp.createTempSync('signature_'));
    tearDown(() => dossier.deleteSync(recursive: true));

    test('un format sans signature sort tel quel, sous son nom', () async {
      final source = File('${dossier.path}/source.docx')
        ..writeAsStringSync('contenu');
      final copie = await SignatureDocument.signer(
        source: source,
        nom: 'Rapport.docx',
        mime: 'application/msword',
        signature: signature(),
        cache: dossier,
      );
      expect(copie.signee, isFalse);
      expect(copie.nom, 'Rapport.docx');
      expect(copie.fichier.path, endsWith('/Rapport.docx'));
      expect(copie.fichier.readAsStringSync(), 'contenu');
    });

    test('si la signature native échoue, la copie sort quand même', () async {
      // Pas de code natif dans les tests : le canal ne répond pas.
      final source = File('${dossier.path}/s.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final copie = await SignatureDocument.signer(
        source: source,
        nom: 'Contrat.pdf',
        mime: 'application/pdf',
        signature: signature(),
        cache: dossier,
      );
      expect(copie.signee, isFalse);
      expect(copie.fichier.readAsStringSync(), '%PDF-1.7');
    });

    test('une vidéo illisible sort telle quelle, sans exception', () async {
      final source = File('${dossier.path}/v.mp4')
        ..writeAsStringSync('pas une vidéo');
      final copie = await SignatureDocument.signer(
        source: source,
        nom: 'v.mp4',
        mime: 'video/mp4',
        signature: signature(),
        cache: dossier,
      );
      expect(copie.signee, isFalse);
      expect(copie.fichier.readAsStringSync(), 'pas une vidéo');
    });

    test(
      'une WebM sans incrustation sort telle quelle, sous son nom',
      () async {
        // Hors Android, pas d'incrustation ; et la WebM n'a pas de métadonnées.
        final source = File('${dossier.path}/v.webm')
          ..writeAsStringSync('webm');
        final copie = await SignatureDocument.signer(
          source: source,
          nom: 'v.webm',
          mime: 'video/webm',
          signature: signature(),
          cache: dossier,
        );
        expect(copie.signee, isFalse);
        expect(copie.nom, 'v.webm');
        expect(copie.fichier.readAsStringSync(), 'webm');
      },
    );
  });
}
