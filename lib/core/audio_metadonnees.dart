import 'dart:convert';
import 'dart:typed_data';

/// L'EMPREINTE D'UN FICHIER AUDIO (25/10/2026, demande du patron).
///
/// Un audio envoyé comme document sensible ne reçoit, à sa sortie, QUE le
/// champ « Empreinte numerique » dans ses métadonnées : rien d'audible, rien
/// d'autre d'écrit. Le format est reconnu à ses OCTETS, pas à son nom :
///
/// * MP3 : une trame ID3v2 `TXXX` (description « Empreinte numerique ») ;
/// * WAV : un bloc `LIST`/`INFO`, commentaire `ICMT` ;
/// * M4A / MP4 audio : un élément libre `----` (`Mp4Metadonnees`, appelé par
///   `SignatureDocument`).
///
/// Les autres (OGG, Opus, FLAC, AMR…) sortent tels quels : le serveur note
/// quand même le geste et son empreinte.
///
/// Le nom du champ s'écrit EN CLAIR dans les octets : `DetecteurCopieSignee`
/// le retrouve, et la copie ne peut pas repartir en document sensible.
enum FormatAudio { mp3, mp4, wav }

const _cle = 'Empreinte numerique';

/// Le format d'un fichier audio, d'après ses premiers octets.
FormatAudio? formatAudio(Uint8List o) {
  if (o.length >= 12 && ascii.decode(o.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(o.sublist(8, 12), allowInvalid: true) == 'WAVE') {
    return FormatAudio.wav;
  }
  if (o.length >= 12 && ascii.decode(o.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    return FormatAudio.mp4;
  }
  if (o.length >= 3 && o[0] == 0x49 && o[1] == 0x44 && o[2] == 0x33) return FormatAudio.mp3;
  // Un MP3 sans étiquette commence par une trame MPEG (11 bits de synchro).
  if (o.length >= 2 && o[0] == 0xFF && (o[1] & 0xE0) == 0xE0) return FormatAudio.mp3;
  return null;
}

int _lireSyncsafe(Uint8List o, int i) =>
    (o[i] & 0x7F) << 21 | (o[i + 1] & 0x7F) << 14 | (o[i + 2] & 0x7F) << 7 | (o[i + 3] & 0x7F);

List<int> _syncsafe(int n) => [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];

List<int> _bigEndian(int n) => [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];

/// La trame `TXXX` de l'empreinte, au format de l'étiquette (v2.3 ou v2.4).
List<int> _trameEmpreinte(String code, int version) {
  final contenu = [0x00, ...latin1.encode(_cle), 0x00, ...latin1.encode(code)];
  return [
    ...ascii.encode('TXXX'),
    ...(version == 4 ? _syncsafe(contenu.length) : _bigEndian(contenu.length)),
    0x00, 0x00,
    ...contenu,
  ];
}

/// Le MP3 avec l'empreinte : ajoutée à l'étiquette ID3v2 existante (v2.3 ou
/// v2.4 simple), ou dans une étiquette v2.3 neuve posée en tête.
/// Lève [FormatException] pour une étiquette qu'on ne sait pas modifier sans risque.
Uint8List avecEmpreinteMp3(Uint8List o, String code) {
  if (o.length >= 10 && o[0] == 0x49 && o[1] == 0x44 && o[2] == 0x33) {
    final version = o[3];
    final drapeaux = o[5];
    if ((version != 3 && version != 4) || drapeaux != 0) {
      throw const FormatException('Étiquette ID3 non prise en charge');
    }
    final taille = _lireSyncsafe(o, 6);
    final fin = 10 + taille;
    if (fin > o.length) throw const FormatException('Étiquette ID3 tronquée');
    // Fin des trames : le premier octet nul (le rembourrage), ou la fin.
    var i = 10;
    while (i + 10 <= fin && o[i] != 0) {
      final t = version == 4 ? _lireSyncsafe(o, i + 4) : (o[i + 4] << 24 | o[i + 5] << 16 | o[i + 6] << 8 | o[i + 7]);
      if (t <= 0 || i + 10 + t > fin) break;
      i += 10 + t;
    }
    final trames = [...o.sublist(10, i), ..._trameEmpreinte(code, version)];
    return Uint8List.fromList([
      ...ascii.encode('ID3'), version, 0, 0,
      ..._syncsafe(trames.length),
      ...trames,
      ...o.sublist(fin),
    ]);
  }
  final trame = _trameEmpreinte(code, 3);
  return Uint8List.fromList([
    ...ascii.encode('ID3'), 3, 0, 0,
    ..._syncsafe(trame.length),
    ...trame,
    ...o,
  ]);
}

/// Le WAV avec l'empreinte : un bloc `LIST`/`INFO` ajouté en fin de fichier,
/// et la taille RIFF mise à jour.
Uint8List avecEmpreinteWav(Uint8List o, String code) {
  if (formatAudio(o) != FormatAudio.wav) throw const FormatException('WAV attendu');
  final texte = [...latin1.encode('$_cle=$code'), 0x00];
  if (texte.length.isOdd) texte.add(0x00);
  List<int> le32(int n) => [n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF];
  final icmt = [...ascii.encode('ICMT'), ...le32(texte.length), ...texte];
  final liste = [...ascii.encode('LIST'), ...le32(4 + icmt.length), ...ascii.encode('INFO'), ...icmt];
  // Un fichier de longueur impaire reçoit l'octet de bourrage RIFF d'abord.
  final corps = [...o, if (o.length.isOdd) 0x00, ...liste];
  final sortie = Uint8List.fromList(corps);
  ByteData.sublistView(sortie).setUint32(4, sortie.length - 8, Endian.little);
  return sortie;
}
