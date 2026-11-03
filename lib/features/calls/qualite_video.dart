import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LA QUALITÉ VIDÉO D'UN APPEL (procédure du patron, 01/11/2026).
///
/// On ne pilote plus la qualité pendant l'appel : WebRTC gère seul les
/// variations du réseau (débit, définition, cadence). Nous fixons seulement
///  - une CAPTURE MAXIMALE, pour que le téléphone ne filme pas plus que
///    nécessaire (processeur, batterie, chauffe) ;
///  - le DÉBIT MAXIMAL de l'encodeur qui va avec.
///
/// L'utilisateur choisit dans son profil, « Réglage appel vidéo ». Le choix
/// est propre à CET appareil : un téléphone n'a pas les contraintes d'un PC.
enum QualiteVideo {
  /// Haute définition : 1280 × 720, 2 Mbit/s.
  haute(1280, 720, 2000000, 'video_quality_high'),

  /// Standard : 640 × 480, 1 Mbit/s. La qualité par défaut.
  standard(640, 480, 1000000, 'video_quality_standard'),

  /// Basse résolution : 640 × 360, 0,4 Mbit/s.
  basse(640, 360, 400000, 'video_quality_low');

  const QualiteVideo(this.largeur, this.hauteur, this.debitMax, this.cleLibelle);

  final int largeur;
  final int hauteur;

  /// En bits par seconde.
  final int debitMax;

  /// La clé du libellé dans `app_localizations.dart`.
  final String cleLibelle;

  /// « 720p — 2 Mbit/s » : le détail technique, sous le libellé.
  String get detail {
    final mbit = debitMax / 1000000;
    final texte = mbit == mbit.roundToDouble()
        ? mbit.toStringAsFixed(0)
        : mbit.toString().replaceAll('.', ',');
    return '${hauteur}p — $texte Mbit/s';
  }

  /// Cadence visée : WebRTC la baisse lui-même si le réseau ou le processeur
  /// ne suivent pas.
  static const cadence = 24;
}

/// Le choix de l'utilisateur, gardé sur l'appareil.
class ReglageQualiteVideo extends ChangeNotifier {
  ReglageQualiteVideo._();
  static final instance = ReglageQualiteVideo._();

  static const _cle = 'appel_video_qualite';

  QualiteVideo _qualite = QualiteVideo.standard;
  bool _charge = false;

  QualiteVideo get qualite => _qualite;

  /// Lit le choix enregistré ; sans effet après la première fois.
  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final p = await SharedPreferences.getInstance();
      final nom = p.getString(_cle);
      _qualite = QualiteVideo.values.firstWhere(
        (q) => q.name == nom,
        orElse: () => QualiteVideo.standard,
      );
      notifyListeners();
    } catch (_) {
      // Préférences illisibles : la qualité par défaut convient.
    }
  }

  Future<void> choisir(QualiteVideo q) async {
    _qualite = q;
    _charge = true;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cle, q.name);
    } catch (_) {}
  }

  /// La qualité d'un appel donné.
  ///
  /// ⚠️ EN GROUPE, PAS AU-DELÀ DE « STANDARD » : chaque téléphone y envoie
  /// sa vidéo à chacun des autres. En haute définition à quatre, cela ferait
  /// 3 × 2 Mbit/s à envoyer, ce qu'un réseau mobile ne tient pas.
  static QualiteVideo pourAppel(QualiteVideo choisie, {required bool groupe}) =>
      groupe && choisie == QualiteVideo.haute ? QualiteVideo.standard : choisie;
}
