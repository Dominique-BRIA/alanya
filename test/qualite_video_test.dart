import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/features/calls/qualite_video.dart';

/// La qualité vidéo des appels (procédure du patron, 01/11/2026).
/// Lancer avec : flutter test test/qualite_video_test.dart
void main() {
  test('les trois qualités : capture et débit maximal', () {
    expect((QualiteVideo.haute.largeur, QualiteVideo.haute.hauteur), (1280, 720));
    expect(QualiteVideo.haute.debitMax, 2000000);
    expect((QualiteVideo.standard.largeur, QualiteVideo.standard.hauteur), (640, 480));
    expect(QualiteVideo.standard.debitMax, 1000000);
    expect((QualiteVideo.basse.largeur, QualiteVideo.basse.hauteur), (640, 360));
    expect(QualiteVideo.basse.debitMax, 400000);
  });

  test('le détail affiché sous le libellé', () {
    expect(QualiteVideo.haute.detail, '720p — 2 Mbit/s');
    expect(QualiteVideo.standard.detail, '480p — 1 Mbit/s');
    expect(QualiteVideo.basse.detail, '360p — 0,4 Mbit/s');
  });

  test('en groupe, pas au-delà de Standard', () {
    expect(ReglageQualiteVideo.pourAppel(QualiteVideo.haute, groupe: true), QualiteVideo.standard);
    expect(ReglageQualiteVideo.pourAppel(QualiteVideo.haute, groupe: false), QualiteVideo.haute);
    expect(ReglageQualiteVideo.pourAppel(QualiteVideo.basse, groupe: true), QualiteVideo.basse);
  });
}
