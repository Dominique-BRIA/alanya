import 'dart:async';

import 'package:flutter/foundation.dart';

/// QUI PARLE, DANS UN APPEL DE GROUPE (06/11/2026), comme WhatsApp et comme
/// l'application de référence.
///
/// Toutes les [intervalle], on lit le niveau sonore de chacun, que fournit le
/// moteur média (`MoteurMedia.niveauxAudio` : `audioLevel` des statistiques
/// WebRTC). Un niveau au-dessus de [seuil] pendant [mesuresPourAllumer]
/// mesures de suite allume l'indicateur ; [mesuresPourEteindre] mesures en
/// dessous l'éteignent. Sans ce délai, il clignoterait à chaque bruit.
///
/// 🔁 07/11/2026 : les niveaux viennent du moteur, et non plus d'une liste de
/// connexions. En SFU, une seule connexion porte la voix de tous : c'est le
/// moteur qui sait à qui appartient chaque piste reçue.
class DetecteurParole {
  DetecteurParole({
    required this.onChange,
    this.seuil = 0.04,
    this.intervalle = const Duration(milliseconds: 350),
    this.mesuresPourAllumer = 2,
    this.mesuresPourEteindre = 4,
  });

  /// La clé de notre propre micro.
  static const moi = '__moi__';

  final VoidCallback onChange;
  final double seuil;
  final Duration intervalle;
  final int mesuresPourAllumer;
  final int mesuresPourEteindre;

  Timer? _minuteur;
  bool _enCours = false;
  final Set<String> _parlent = {};
  final Map<String, int> _audessus = {};
  final Map<String, int> _endessous = {};

  /// Les identifiants de ceux qui parlent ([moi] compris).
  Set<String> get parlent => Set.unmodifiable(_parlent);

  bool parle(String id) => _parlent.contains(id);

  /// [niveaux] rend le niveau de chacun (et le nôtre sous [moi]), ou `null`
  /// quand il n'y a encore rien à mesurer.
  void demarrer(Future<Map<String, double>?> Function() niveaux) {
    _minuteur?.cancel();
    _minuteur = Timer.periodic(intervalle, (_) => _sonder(niveaux));
  }

  void arreter() {
    _minuteur?.cancel();
    _minuteur = null;
    _audessus.clear();
    _endessous.clear();
    if (_parlent.isNotEmpty) {
      _parlent.clear();
      onChange();
    }
  }

  Future<void> _sonder(Future<Map<String, double>?> Function() niveaux) async {
    // Plusieurs lectures de suite peuvent dépasser l'intervalle : sans cette
    // garde, les sondages se chevaucheraient et les compteurs avanceraient deux
    // fois plus vite que prévu.
    if (_enCours) return;
    _enCours = true;
    var change = false;
    try {
      final lus = await niveaux();
      if (lus == null) return;
      for (final e in lus.entries) {
        change |= mesurer(e.key, e.value);
      }
      // Un participant parti ne parle plus.
      for (final id in _parlent.toList()) {
        if (id != moi && !lus.containsKey(id)) {
          _parlent.remove(id);
          change = true;
        }
      }
    } catch (_) {
      // Moteur en cours de fermeture : rien à mesurer ce tour-ci.
    } finally {
      _enCours = false;
    }
    if (change) onChange();
  }

  /// Enregistre une mesure. Vrai si l'état de [id] vient de changer.
  @visibleForTesting
  bool mesurer(String id, double niveau) {
    if (niveau >= seuil) {
      _endessous[id] = 0;
      final n = (_audessus[id] ?? 0) + 1;
      _audessus[id] = n;
      if (n >= mesuresPourAllumer && _parlent.add(id)) return true;
    } else {
      _audessus[id] = 0;
      final n = (_endessous[id] ?? 0) + 1;
      _endessous[id] = n;
      if (n >= mesuresPourEteindre && _parlent.remove(id)) return true;
    }
    return false;
  }
}
