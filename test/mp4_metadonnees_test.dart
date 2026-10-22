import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alanya/core/mp4_metadonnees.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les métadonnées d'une vidéo sensible (22/10/2026) : écrites sans casser la
/// vidéo. Le point dangereux est `moov` placé AVANT les données : l'agrandir
/// décale tout, et chaque position de morceau doit suivre.
void main() {
  late Directory dossier;

  setUp(() => dossier = Directory.systemTemp.createTempSync('mp4_meta_'));
  tearDown(() => dossier.deleteSync(recursive: true));

  const elements = ElementsMp4(
    standard: {
      '©too': 'Alanya Work',
      '©cmt': 'Alanya Work · Alanya 67 64 15 99 · samsung SM-A515F',
      '©ART': 'Alanya 67 64 15 99',
    },
    libres: {'trace': '0123456789abcdef0123456789abcdef', 'geste': 'PARTAGE'},
  );

  for (final moovDevant in [true, false]) {
    for (final grand in [false, true]) {
      test(
        'moov ${moovDevant ? 'devant' : 'derrière'} les données, '
        '${grand ? 'co64' : 'stco'} : chaque morceau reste à sa place',
        () async {
          final (octets, morceaux) = _videoFactice(
            moovDevant: moovDevant,
            co64: grand,
          );
          final entree = File('${dossier.path}/e.mp4')
            ..writeAsBytesSync(octets);
          final sortie = File('${dossier.path}/s.mp4');

          await Mp4Metadonnees.ecrire(entree, sortie, elements);

          final lu = sortie.readAsBytesSync();
          final positions = _positions(lu);
          expect(positions, hasLength(morceaux.length));
          for (var i = 0; i < morceaux.length; i++) {
            expect(
              lu.sublist(positions[i], positions[i] + morceaux[i].length),
              morceaux[i],
            );
          }
          final items = _items(lu);
          expect(items['©too'], 'Alanya Work');
          expect(items['©ART'], 'Alanya 67 64 15 99');
          expect(items['----:trace'], '0123456789abcdef0123456789abcdef');
          expect(items['----:geste'], 'PARTAGE');
        },
      );
    }
  }

  test(
    're-signer remplace la trace, et garde les éléments des autres',
    () async {
      final (octets, morceaux) = _videoFactice(
        moovDevant: true,
        ilstExistante: {'©nam': 'Réunion du lundi', '©too': 'Lavf60'},
      );
      final entree = File('${dossier.path}/e.mp4')..writeAsBytesSync(octets);
      final une = File('${dossier.path}/1.mp4');
      final deux = File('${dossier.path}/2.mp4');

      await Mp4Metadonnees.ecrire(entree, une, elements);
      await Mp4Metadonnees.ecrire(
        une,
        deux,
        const ElementsMp4(
          standard: {'©too': 'Alanya Work'},
          libres: {'trace': 'ffffffffffffffffffffffffffffffff'},
        ),
      );

      final lu = deux.readAsBytesSync();
      final tous = _tousLesItems(lu);
      expect(tous.where((e) => e.key == '----:trace').map((e) => e.value), [
        'ffffffffffffffffffffffffffffffff',
      ]);
      expect(tous.where((e) => e.key == '©too'), hasLength(1));
      expect(_items(lu)['©nam'], 'Réunion du lundi');
      final positions = _positions(lu);
      for (var i = 0; i < morceaux.length; i++) {
        expect(
          lu.sublist(positions[i], positions[i] + morceaux[i].length),
          morceaux[i],
        );
      }
    },
  );

  test(
    "ce qui n'est pas un MP4 est refusé, sans rien écrire de faux",
    () async {
      final entree = File('${dossier.path}/e.pdf')
        ..writeAsBytesSync(utf8.encode('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n'));
      expect(
        () =>
            Mp4Metadonnees.ecrire(entree, File('${dossier.path}/s'), elements),
        throwsFormatException,
      );
    },
  );

  test('une vidéo fragmentée après moov est refusée', () async {
    final (octets, _) = _videoFactice(moovDevant: true, fragmentee: true);
    final entree = File('${dossier.path}/e.mp4')..writeAsBytesSync(octets);
    expect(
      () => Mp4Metadonnees.ecrire(
        entree,
        File('${dossier.path}/s.mp4'),
        elements,
      ),
      throwsFormatException,
    );
  });

  test('les types pris en charge', () {
    expect(Mp4Metadonnees.prisEnCharge('video/mp4', 'a.bin'), isTrue);
    expect(
      Mp4Metadonnees.prisEnCharge('application/octet-stream', 'A.MOV'),
      isTrue,
    );
    expect(Mp4Metadonnees.prisEnCharge('video/webm', 'a.webm'), isFalse);
    expect(Mp4Metadonnees.prisEnCharge('application/pdf', 'a.pdf'), isFalse);
  });
}

// ── fabrication d'une vidéo factice ─────────────────────────────────────

Uint8List _b(String type, List<int> charge) {
  final d = ByteData(8 + charge.length)..setUint32(0, 8 + charge.length);
  final o = d.buffer.asUint8List();
  o.setRange(4, 8, latin1.encode(type));
  o.setRange(8, o.length, charge);
  return o;
}

/// ftyp + moov (trak/mdia/minf/stbl/stco|co64) + mdat, dans l'ordre voulu.
/// Rend le fichier et les morceaux que les positions doivent désigner.
(Uint8List, List<List<int>>) _videoFactice({
  required bool moovDevant,
  bool co64 = false,
  bool fragmentee = false,
  Map<String, String>? ilstExistante,
}) {
  final morceaux = [
    for (var i = 0; i < 3; i++)
      List<int>.generate(50 + i * 7, (j) => (i * 31 + j) & 0xFF),
  ];
  final ftyp = _b('ftyp', [
    ...latin1.encode('isom'),
    0,
    0,
    2,
    0,
    ...latin1.encode('isommp41'),
  ]);
  final charge = morceaux.expand((m) => m).toList();

  Uint8List moovAvec(int debutDonnees) {
    final positions = <int>[];
    var p = debutDonnees;
    for (final m in morceaux) {
      positions.add(p);
      p += m.length;
    }
    final table = ByteData(8 + positions.length * (co64 ? 8 : 4))
      ..setUint32(4, positions.length);
    for (var i = 0; i < positions.length; i++) {
      co64
          ? table.setUint64(8 + i * 8, positions[i])
          : table.setUint32(8 + i * 4, positions[i]);
    }
    final stbl = _b(
      'stbl',
      _b(co64 ? 'co64' : 'stco', table.buffer.asUint8List()),
    );
    final trak = _b('trak', [
      ..._b('tkhd', List.filled(84, 0)),
      ..._b('mdia', _b('minf', stbl)),
    ]);
    final udta = ilstExistante == null
        ? <int>[]
        : _b(
            'udta',
            _b('meta', [
              0,
              0,
              0,
              0,
              ..._b('hdlr', [
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                ...latin1.encode('mdirappl'),
                ...List.filled(9, 0),
              ]),
              ..._b('ilst', [
                for (final e in ilstExistante.entries)
                  ..._b(
                    e.key,
                    _b('data', [
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      ...utf8.encode(e.value),
                    ]),
                  ),
              ]),
            ]),
          );
    return _b('moov', [..._b('mvhd', List.filled(100, 0)), ...trak, ...udta]);
  }

  final fragment = fragmentee ? _b('moof', List.filled(16, 0)) : Uint8List(0);
  if (moovDevant) {
    // Deux passes : la taille de moov fixe le début des données.
    final essai = moovAvec(0);
    final debut = ftyp.length + essai.length + 8;
    final moov = moovAvec(debut);
    return (
      Uint8List.fromList([
        ...ftyp,
        ...moov,
        ..._b('mdat', charge),
        ...fragment,
      ]),
      morceaux,
    );
  }
  final debut = ftyp.length + 8;
  final moov = moovAvec(debut);
  return (
    Uint8List.fromList([...ftyp, ..._b('mdat', charge), ...moov]),
    morceaux,
  );
}

// ── relecture ───────────────────────────────────────────────────────────

class _B {
  _B(this.type, this.charge, this.fin);
  final String type;
  final int charge;
  final int fin;
}

List<_B> _enfants(Uint8List d, int debut, int fin) {
  final r = <_B>[];
  final v = ByteData.sublistView(d);
  var p = debut;
  while (p + 8 <= fin) {
    final t = v.getUint32(p);
    r.add(_B(latin1.decode(d.sublist(p + 4, p + 8)), p + 8, p + t));
    p += t;
  }
  return r;
}

_B _trouver(Uint8List d, List<String> chemin) {
  var debut = 0;
  var fin = d.length;
  late _B b;
  for (final type in chemin) {
    b = _enfants(d, debut, fin).firstWhere((e) => e.type == type);
    debut = b.charge + (type == 'meta' ? 4 : 0);
    fin = b.fin;
  }
  return b;
}

List<int> _positions(Uint8List d) {
  final v = ByteData.sublistView(d);
  final stbl = _trouver(d, ['moov', 'trak', 'mdia', 'minf', 'stbl']);
  final t = _enfants(d, stbl.charge, stbl.fin).single;
  final n = v.getUint32(t.charge + 4);
  return [
    for (var i = 0; i < n; i++)
      t.type == 'co64'
          ? v.getUint64(t.charge + 8 + i * 8)
          : v.getUint32(t.charge + 8 + i * 4),
  ];
}

List<MapEntry<String, String>> _tousLesItems(Uint8List d) {
  final ilst = _trouver(d, ['moov', 'udta', 'meta', 'ilst']);
  final r = <MapEntry<String, String>>[];
  for (final item in _enfants(d, ilst.charge, ilst.fin)) {
    var cle = item.type;
    String? valeur;
    for (final e in _enfants(d, item.charge, item.fin)) {
      if (e.type == 'name')
        cle = '----:${utf8.decode(d.sublist(e.charge + 4, e.fin))}';
      if (e.type == 'data')
        valeur = utf8.decode(d.sublist(e.charge + 8, e.fin));
    }
    r.add(MapEntry(cle, valeur ?? ''));
  }
  return r;
}

Map<String, String> _items(Uint8List d) => Map.fromEntries(_tousLesItems(d));
