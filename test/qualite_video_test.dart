import 'package:flutter_test/flutter_test.dart';
import 'package:alanya/features/calls/qualite_video.dart';

/// La qualité vidéo des appels (tableau du patron, 06/11/2026).
/// Lancer avec : flutter test test/qualite_video_test.dart
void main() {
  test('les quatre qualités : capture, cadence et débit maximal', () {
    void verifie(QualiteVideo q, int l, int h, int images, int debit) {
      expect((q.largeur, q.hauteur, q.cadence, q.debitMax), (l, h, images, debit));
    }

    verifie(QualiteVideo.fullHd, 1920, 1080, 30, 5000000);
    verifie(QualiteVideo.haute, 1280, 720, 30, 2500000);
    verifie(QualiteVideo.standard, 854, 480, 30, 1200000);
    verifie(QualiteVideo.basse, 640, 360, 20, 600000);
  });

  test('le détail affiché sous le libellé', () {
    expect(QualiteVideo.fullHd.detail, '1080p — 5 Mbit/s');
    expect(QualiteVideo.haute.detail, '720p — 2,5 Mbit/s');
    expect(QualiteVideo.standard.detail, '480p — 1,2 Mbit/s');
    expect(QualiteVideo.basse.detail, '360p — 0,6 Mbit/s');
  });

  test('en groupe, pas au-delà de Standard', () {
    QualiteVideo g(QualiteVideo q) => ReglageQualiteVideo.pourAppel(q, groupe: true);
    expect(g(QualiteVideo.fullHd), QualiteVideo.standard);
    expect(g(QualiteVideo.haute), QualiteVideo.standard);
    expect(g(QualiteVideo.basse), QualiteVideo.basse);
    expect(ReglageQualiteVideo.pourAppel(QualiteVideo.fullHd, groupe: false), QualiteVideo.fullHd);
  });
}
