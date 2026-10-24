import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:alanya/core/detecteur_copie_signee.dart';
import 'package:alanya/core/protection_pdf_copie.dart';
import 'package:alanya/core/signature_document.dart';
import 'package:alanya/services/e2ee/e2ee_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Un PDF de deux pages, comme en enverrait quelqu'un.
Uint8List _pdfSource() {
  final doc = PdfDocument();
  for (final t in ['Contrat confidentiel', 'Page deux']) {
    doc.pages.add().graphics.drawString(
      t,
      PdfStandardFont(PdfFontFamily.helvetica, 18),
      bounds: const Rect.fromLTWH(40, 80, 400, 40),
    );
  }
  final o = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return o;
}

const _meta = {
  'Application': 'Alanya Work',
  'Alanya ID': '83 79 23 76',
  'Empreinte numerique': '0123456789abcdef0123456789abcdef',
  'Geste': 'TELECHARGEMENT',
};

void main() {
  group('ProtectionPdf (descripteur)', () {
    test('aller-retour JSON, mot de passe d\'ouverture facultatif', () {
      const avec = ProtectionPdf(
        imprimer: false,
        ouverture: 'ouvre-moi',
        proprietaire: 'proprio-42',
      );
      final relu = ProtectionPdf.depuisJson(avec.toJson());
      expect(relu.imprimer, isFalse);
      expect(relu.ouverture, 'ouvre-moi');
      expect(relu.proprietaire, 'proprio-42');
      expect(relu.avecMotDePasse, isTrue);

      final sans = ProtectionPdf.depuisJson({
        'imprimer': false,
        'proprietaire': 'x',
      });
      expect(sans.avecMotDePasse, isFalse);
      expect(sans.toJson().containsKey('ouverture'), isFalse);
    });

    test('refuse une protection mal formée', () {
      for (final brut in [
        'non',
        {'imprimer': 'oui', 'proprietaire': 'x'},
        {'imprimer': true},
        {'imprimer': true, 'proprietaire': ''},
        {'imprimer': true, 'proprietaire': 'x', 'ouverture': ''},
      ]) {
        expect(() => ProtectionPdf.depuisJson(brut), throwsA(isA<ChargeInvalide>()));
      }
    });

    test('un descripteur sans protection ne change pas d\'un octet', () {
      final d = DescripteurMedia.depuisJson({
        'id': 'm1',
        'cle': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'empreinte': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'taille': 10,
        'mime': 'application/pdf',
        'sensible': true,
      });
      expect(d.protection, isNull);
      expect(d.toJson().containsKey('protection'), isFalse);
    });

    test('le propriétaire tiré au hasard est long et varié', () {
      final a = ProtectionPdf.proprietaireAuHasard();
      expect(a.length, 24);
      expect(a, isNot(ProtectionPdf.proprietaireAuHasard()));
    });
  });

  group('protegerPdf (Syncfusion)', () {
    test('avec mot de passe : chiffré, numéro au coin, empreinte détectable', () {
      final sortie = protegerPdf(
        CopiePdfProtegee(
          octets: _pdfSource(),
          protection: const ProtectionPdf(
            imprimer: false,
            ouverture: 'ouvre-moi',
            proprietaire: 'proprio-42',
          ),
          coin: '83792376',
          meta: _meta,
        ),
      );
      final dossier = Platform.environment['ALANYA_PDF_SORTIE'];
      if (dossier != null) {
        File('$dossier/protege-mdp.pdf').writeAsBytesSync(sortie);
      }
      expect(DetecteurCopieSignee.contientSignature(sortie), isTrue);
      // Sans mot de passe, la bibliothèque elle-même refuse de l'ouvrir.
      expect(() => PdfDocument(inputBytes: sortie), throwsA(anything));
      final ouvert = PdfDocument(inputBytes: sortie, password: 'ouvre-moi');
      expect(ouvert.pages.count, 2);
      final texte = PdfTextExtractor(ouvert).extractText();
      expect(texte, contains('83792376'));
      expect(texte, isNot(contains('AlanyaID')));
      ouvert.dispose();
    });

    test('sans mot de passe : s\'ouvre, impression retirée', () {
      final sortie = protegerPdf(
        CopiePdfProtegee(
          octets: _pdfSource(),
          protection: ProtectionPdf(
            imprimer: false,
            proprietaire: ProtectionPdf.proprietaireAuHasard(),
          ),
          meta: _meta,
        ),
      );
      final dossier = Platform.environment['ALANYA_PDF_SORTIE'];
      if (dossier != null) {
        File('$dossier/protege-sans-mdp.pdf').writeAsBytesSync(sortie);
      }
      expect(DetecteurCopieSignee.contientSignature(sortie), isTrue);
      final ouvert = PdfDocument(inputBytes: sortie);
      expect(ouvert.pages.count, 2);
      ouvert.dispose();
    });
  });

  group('SignatureDocument.signer avec protection', () {
    SignatureSortie signature() => SignatureSortie(
      geste: GesteSortie.telechargement,
      alanyaId: '83792376',
      appareil: 'banc',
      quand: DateTime(2026, 10, 24, 18),
      code: '0123456789abcdef0123456789abcdef',
    );
    const protection = ProtectionPdf(
      imprimer: false,
      ouverture: 'ouvre-moi',
      proprietaire: 'proprio-42',
    );

    test('le numéro seul est en chiffres', () {
      expect(signature().numeroSeul, '83792376');
    });

    test('la copie téléchargée est chiffrée, au nom de qui télécharge', () async {
      final dossier = await Directory.systemTemp.createTemp('pdfp');
      addTearDown(() => dossier.delete(recursive: true));
      final source = File('${dossier.path}/contrat.pdf')
        ..writeAsBytesSync(_pdfSource());
      final c = await SignatureDocument.signer(
        source: source,
        nom: 'contrat.pdf',
        mime: 'application/pdf',
        signature: signature(),
        cache: dossier,
        protection: protection,
      );
      expect(c.signee, isTrue);
      expect(c.nom, 'contrat.pdf');
      final octets = c.fichier.readAsBytesSync();
      expect(DetecteurCopieSignee.contientSignature(octets), isTrue);
      final doc = PdfDocument(inputBytes: octets, password: 'ouvre-moi');
      expect(PdfTextExtractor(doc).extractText(), contains('83792376'));
      doc.dispose();
    });

    test('un PDF illisible n\'est PAS rendu tel quel : rien ne sort', () async {
      final dossier = await Directory.systemTemp.createTemp('pdfp');
      addTearDown(() => dossier.delete(recursive: true));
      final source = File('${dossier.path}/abime.pdf')
        ..writeAsBytesSync([1, 2, 3, 4]);
      await expectLater(
        SignatureDocument.signer(
          source: source,
          nom: 'abime.pdf',
          mime: 'application/pdf',
          signature: signature(),
          cache: dossier,
          protection: protection,
        ),
        throwsA(isA<ProtectionImpossible>()),
      );
    });
  });
}
