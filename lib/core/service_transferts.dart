import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'centre_transferts.dart';

/// Pont vers le service de premier plan qui tient les transferts en vie.
///
/// 🔴 **CE QUE LES NOTIFICATIONS NE FONT PAS.** Une barre de progression MONTRE
/// où en est un transfert ; elle ne le fait pas avancer. Le transfert est une
/// requête HTTP portée par l'isolat Dart, donc par le processus de
/// l'application — qu'Android suspend puis tue en arrière-plan. Sans service de
/// premier plan, quitter Alanya pendant l'envoi d'une vidéo laissait une barre
/// figée sur un transfert mort.
///
/// Le canal est celui de `MainActivity` (`alanya/ecran_verrouille`), déjà en
/// place pour le service d'appel : en ouvrir un second aurait doublé le câblage
/// natif pour la même activité.
class ServiceTransferts {
  ServiceTransferts._();

  static const _canal = MethodChannel('alanya/ecran_verrouille');

  /// Vrai quand le service tourne, pour ne pas le redémarrer à chaque pour cent.
  static bool _actif = false;

  static bool get _disponible => !kIsWeb && Platform.isAndroid;

  /// Branche le service sur l'activité du centre de transferts.
  ///
  /// Le centre ne connaît ni Android ni les canaux : c'est ce qui lui permet de
  /// servir aussi bien un envoi qu'un modèle de langue. Le lien se fait ici.
  ///
  /// ⚠️ **La langue est EXCLUE du décompte.** Son téléchargement est mené par
  /// les services Google Play, dans LEUR processus : il survit déjà à tout, et
  /// tenir le nôtre éveillé pour l'attendre ne ferait que consommer de la
  /// batterie sans rien protéger.
  static void brancher() {
    if (!_disponible) return;
    CentreTransferts.instance.addListener(_reagir);
  }

  static void _reagir() {
    final enCours = CentreTransferts.instance.enCours
        .where((t) => t.sorte != SorteTransfert.langue)
        .toList();
    if (enCours.isEmpty) {
      _arreter();
      return;
    }
    _demarrer(
      enCours.length == 1
          ? enCours.first.sousTitreNotification
          : "${enCours.length} transferts en cours",
    );
  }

  static Future<void> _demarrer(String texte) async {
    // Le texte n'est posé qu'au DÉMARRAGE : le rafraîchir à chaque pour cent
    // ferait un aller-retour natif par octet, pour un badge que personne ne lit
    // — les barres de progression, elles, sont posées par Flutter.
    if (_actif) return;
    _actif = true;
    try {
      await _canal.invokeMethod('demarrerServiceTransferts', {'texte': texte});
    } catch (_) {
      // Un refus du système — service `dataSync` interdit depuis
      // l'arrière-plan sur Android 12+ — ne doit PAS interrompre le transfert.
      // Il continuera simplement sans protection.
      _actif = false;
    }
  }

  static Future<void> _arreter() async {
    if (!_actif) return;
    _actif = false;
    try {
      await _canal.invokeMethod('arreterServiceTransferts');
    } catch (_) {}
  }
}
