import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/core/detecteur_copie_signee.dart';
import 'package:alanya/core/mp4_metadonnees.dart';
import 'package:alanya/core/signature_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une copie signée ne repart pas en « sensible » (24/10/2026) : on la
/// reconnaît à ses champs de métadonnées, quel que soit le format.
void main() {
  Uint8List octets(String s) => Uint8List.fromList(latin1.encode(s));

  test('un PDF signé (nom de champ encodé dans le dictionnaire Info)', () {
    expect(
      DetecteurCopieSignee.contientSignature(
        octets(
          '%PDF-1.7\n9 0 obj\n<< /Creator (Alanya Work) /Empreinte#20numerique (3f9a) >>\nendobj',
        ),
      ),
      isTrue,
    );
  });

  test('une image signée (commentaire EXIF ou bloc iTXt)', () {
    expect(
      DetecteurCopieSignee.contientSignature(
        octets(
          '\xFF\xD8\xFF\xE1..Exif..ASCII\x00\x00\x00Application=Alanya Work; Empreinte numerique=3f9a',
        ),
      ),
      isTrue,
    );
  });

  test('une copie sortie du 22 au 24/10, sous les anciens noms', () {
    expect(
      DetecteurCopieSignee.contientSignature(octets('/AlanyaTrace (3f9a)')),
      isTrue,
    );
    expect(
      DetecteurCopieSignee.contientSignature(
        octets('mean....com.alanya237.work'),
      ),
      isTrue,
    );
  });

  test('un document ordinaire passe', () {
    expect(
      DetecteurCopieSignee.contientSignature(
        octets(
          '%PDF-1.7\n<< /Creator (Microsoft Word) /Title (Empreinte du projet) >>',
        ),
      ),
      isFalse,
    );
    expect(DetecteurCopieSignee.contientSignature(Uint8List(0)), isFalse);
  });

  test('une vraie vidéo signée par le moteur, retrouvée', () async {
    final dossier = Directory.systemTemp.createTempSync('copie_signee_');
    addTearDown(() => dossier.deleteSync(recursive: true));
    // ftyp + moov minimal + mdat.
    Uint8List b(String type, List<int> charge) {
      final d = ByteData(8 + charge.length)..setUint32(0, 8 + charge.length);
      final o = d.buffer.asUint8List();
      o.setRange(4, 8, latin1.encode(type));
      o.setRange(8, o.length, charge);
      return o;
    }

    final entree = File('${dossier.path}/v.mp4')
      ..writeAsBytesSync([
        ...b('ftyp', latin1.encode('isom\x00\x00\x02\x00isom')),
        ...b('moov', b('mvhd', List.filled(100, 0))),
        ...b('mdat', List.filled(64, 7)),
      ]);
    expect(
      await DetecteurCopieSignee.estCopieSignee(entree.readAsBytesSync()),
      isFalse,
    );

    final sortie = File('${dossier.path}/s.mp4');
    final s = SignatureSortie(
      geste: GesteSortie.telechargement,
      alanyaId: '67641599',
      appareil: 'samsung SM-A515F',
      quand: DateTime(2026, 10, 24),
      code: '3f9a0c1e5b7d2a4c6e8f0a1b2c3d4e5f',
    );
    await Mp4Metadonnees.ecrire(entree, sortie, s.elementsMp4);
    expect(
      await DetecteurCopieSignee.estCopieSignee(sortie.readAsBytesSync()),
      isTrue,
    );
  });
}
