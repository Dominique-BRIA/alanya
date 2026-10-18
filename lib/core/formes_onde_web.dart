import 'formes_onde_commun.dart';

/// Web : pas d'extraction (`audio_waveforms` n'existe que sur Android et iOS),
/// des barres déterministes — la même forme à chaque affichage.
class FormesOnde {
  FormesOnde._();

  static Future<List<double>> pour({
    required String cheminLocal,
    required int dureeSecondes,
  }) async =>
      formeOndeDeRepli(cheminLocal, dureeSecondes);
}
