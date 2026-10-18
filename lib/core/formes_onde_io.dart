import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'formes_onde_commun.dart';

/// La forme d'onde RÉELLE d'un message vocal, extraite du fichier.
///
/// 🔴 « LE VOCAL N'EST PAS BEAU, AVANT IL Y AVAIT UN TRAIT AU MILIEU » (patron,
/// 18/10/2026). Repris de l'application Talky de l'équipe
/// (`VoiceWaveformStore`) : extraction par `audio_waveforms`, gardée en
/// mémoire et sur le disque — on ne la recalcule pas à chaque affichage.
///
/// ⚠️ NE LÈVE JAMAIS ET NE REND JAMAIS VIDE : échec, fichier absent ou délai
/// dépassé, on rend des barres déterministes (`formeOndeDeRepli`).
///
/// ⚠️ UNE EXTRACTION À LA FOIS : un fil plein de vocaux en lancerait des
/// dizaines en parallèle sur le décodeur du téléphone.
class FormesOnde {
  FormesOnde._();

  static final Map<String, List<double>> _memoire = {};
  static Future<void>? _file;
  static Directory? _dossier;

  static Future<List<double>> pour({
    required String cheminLocal,
    required int dureeSecondes,
  }) async {
    try {
      final f = File(cheminLocal);
      if (!f.existsSync()) return formeOndeDeRepli(cheminLocal, dureeSecondes);
      final st = f.statSync();
      final cle = '${p.basename(cheminLocal)}_${st.size}'
          .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final enMemoire = _memoire[cle];
      if (enMemoire != null) return enMemoire;

      final surDisque = await _lire(cle);
      if (surDisque != null && surDisque.isNotEmpty) {
        return _memoire[cle] = surDisque;
      }

      final extraite = await _uneALaFois(() => _extraire(cheminLocal));
      final forme = (extraite != null && extraite.isNotEmpty)
          ? extraite
          : formeOndeDeRepli(cheminLocal, dureeSecondes);
      _memoire[cle] = forme;
      unawaited(_ecrire(cle, forme));
      return forme;
    } catch (e) {
      debugPrint('[FormesOnde] repli : $e');
      return formeOndeDeRepli(cheminLocal, dureeSecondes);
    }
  }

  static Future<T> _uneALaFois<T>(Future<T> Function() travail) async {
    final precedent = _file ?? Future<void>.value();
    final porte = Completer<void>();
    _file = porte.future;
    await precedent;
    try {
      return await travail();
    } finally {
      porte.complete();
    }
  }

  static Future<List<double>?> _extraire(String chemin) async {
    final extracteur = WaveformExtractionController();
    try {
      final donnees = await extracteur
          .extractWaveformData(path: chemin, noOfSamples: barresFormeOnde)
          .timeout(const Duration(seconds: 15));
      return donnees.isEmpty ? null : List<double>.from(donnees);
    } catch (e) {
      debugPrint('[FormesOnde] extraction impossible : $e');
      return null;
    } finally {
      try {
        await extracteur.stopWaveformExtraction();
      } catch (_) {}
    }
  }

  static Future<Directory> _repertoire() async {
    if (_dossier != null) return _dossier!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'formes_onde'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dossier = d;
  }

  static Future<List<double>?> _lire(String cle) async {
    try {
      final f = File(p.join((await _repertoire()).path, '$cle.json'));
      if (!f.existsSync()) return null;
      final brut = jsonDecode(await f.readAsString());
      if (brut is! List) return null;
      return [for (final v in brut) (v as num).toDouble()];
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ecrire(String cle, List<double> forme) async {
    try {
      final f = File(p.join((await _repertoire()).path, '$cle.json'));
      await f.writeAsString(jsonEncode(forme));
    } catch (_) {}
  }
}
