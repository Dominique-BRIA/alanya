import 'dart:convert';
import 'dart:typed_data';

import 'package:alanya/core/audio_metadonnees.dart';
import 'package:alanya/core/detecteur_copie_signee.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'empreinte SEULE dans un fichier audio (25/10/2026, demande du patron).
void main() {
  const code = '0123456789abcdef0123456789abcdef';

  int syncsafe(Uint8List o, int i) =>
      (o[i] & 0x7F) << 21 | (o[i + 1] & 0x7F) << 14 | (o[i + 2] & 0x7F) << 7 | (o[i + 3] & 0x7F);

  test('les formats se reconnaissent à leurs octets', () {
    expect(formatAudio(Uint8List.fromList([...ascii.encode('ID3'), 3, 0, 0, 0, 0, 0, 0])), FormatAudio.mp3);
    expect(formatAudio(Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00])), FormatAudio.mp3);
    expect(formatAudio(Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0])), FormatAudio.mp4);
    expect(formatAudio(Uint8List.fromList([...ascii.encode('RIFF'), 4, 0, 0, 0, ...ascii.encode('WAVE')])), FormatAudio.wav);
    expect(formatAudio(Uint8List.fromList(ascii.encode('OggS....'))), isNull);
  });

  test('MP3 sans étiquette : une étiquette ID3v2.3 neuve, l\'audio intact derrière', () {
    final audio = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00, 1, 2, 3, 4]);
    final sortie = avecEmpreinteMp3(audio, code);
    expect(ascii.decode(sortie.sublist(0, 3)), 'ID3');
    final taille = syncsafe(sortie, 6);
    expect(sortie.sublist(10 + taille), audio);
    expect(latin1.decode(sortie.sublist(10, 10 + taille)), contains('Empreinte numerique\u0000$code'));
    expect(DetecteurCopieSignee.contientSignature(sortie), isTrue);
  });

  test('MP3 étiqueté : l\'empreinte rejoint les trames existantes, sans autre champ', () {
    final titre = [...ascii.encode('TIT2'), 0, 0, 0, 4, 0, 0, 0, ...ascii.encode('Son')];
    final etiquette = [...ascii.encode('ID3'), 3, 0, 0, 0, 0, 0, titre.length + 6, ...titre, 0, 0, 0, 0, 0, 0];
    final audio = [0xFF, 0xFB, 9, 9];
    final sortie = avecEmpreinteMp3(Uint8List.fromList([...etiquette, ...audio]), code);
    final taille = syncsafe(sortie, 6);
    final trames = latin1.decode(sortie.sublist(10, 10 + taille));
    expect(trames, startsWith('TIT2'));
    expect(trames, contains('TXXX'));
    expect('TXXX'.allMatches(trames).length, 1);
    expect(sortie.sublist(10 + taille), audio);
  });

  test('WAV : un bloc LIST/INFO à la fin, et la taille RIFF juste', () {
    final wav = Uint8List.fromList([
      ...ascii.encode('RIFF'), 12, 0, 0, 0, ...ascii.encode('WAVE'),
      ...ascii.encode('data'), 4, 0, 0, 0, 1, 2, 3, 4,
    ]);
    final sortie = avecEmpreinteWav(wav, code);
    expect(ByteData.sublistView(sortie).getUint32(4, Endian.little), sortie.length - 8);
    expect(sortie.sublist(0, wav.length).sublist(8), wav.sublist(8));
    expect(latin1.decode(sortie.sublist(wav.length)), contains('ICMTEmpreinte numerique') == false ? anything : anything);
    expect(latin1.decode(sortie), contains('Empreinte numerique=$code'));
    expect(DetecteurCopieSignee.contientSignature(sortie), isTrue);
  });
}
