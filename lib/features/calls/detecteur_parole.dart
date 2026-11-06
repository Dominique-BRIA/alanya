import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// QUI PARLE, DANS UN APPEL DE GROUPE (06/11/2026), comme WhatsApp et comme
/// l'application de référence.
///
/// Toutes les [intervalle], on lit `audioLevel` dans les statistiques WebRTC :
/// `inbound-rtp` pour la voix reçue de chaque participant, `media-source` pour
/// notre propre micro. Un niveau au-dessus de [seuil] pendant [mesuresPourAllumer]
/// mesures de suite allume l'indicateur ; [mesuresPourEteindre] mesures en
/// dessous l'éteignent. Sans ce délai, il clignoterait à chaque bruit.
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

  void demarrer(Map<String, RTCPeerConnection> Function() connexions) {
    _minuteur?.cancel();
    _minuteur = Timer.periodic(intervalle, (_) => _sonder(connexions()));
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

  Future<void> _sonder(Map<String, RTCPeerConnection> connexions) async {
    // Plusieurs `getStats` de suite peuvent dépasser l'intervalle : sans cette
    // garde, les sondages se chevaucheraient et les compteurs avanceraient deux
    // fois plus vite que prévu.
    if (_enCours || connexions.isEmpty) return;
    _enCours = true;
    var change = false;
    try {
      var moiLu = false;
      final vus = <String>{};
      for (final e in connexions.entries) {
        try {
          final rapports = await e.value.getStats();
          for (final r in rapports) {
            final v = r.values;
            if (v['kind'] != 'audio') continue;
            final niveau = (v['audioLevel'] as num?)?.toDouble();
            if (niveau == null) continue;
            if (r.type == 'inbound-rtp') {
              change |= mesurer(e.key, niveau);
              vus.add(e.key);
            } else if (!moiLu && r.type == 'media-source') {
              // Le même micro pour toutes les liaisons : une lecture suffit.
              change |= mesurer(moi, niveau);
              moiLu = true;
            }
          }
        } catch (_) {
          // Liaison en cours de fermeture : elle sera absente au tour suivant.
        }
      }
      // Un participant parti ne parle plus.
      for (final id in _parlent.toList()) {
        if (id != moi && !connexions.containsKey(id)) {
          _parlent.remove(id);
          change = true;
        }
      }
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
