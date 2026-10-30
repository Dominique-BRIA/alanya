import 'dart:async';

import 'package:flutter/foundation.dart';

import 'realtime_client.dart';

/// Observe l'état de connectivité (online/offline) de l'app.
///
/// 🐛 « EN ATTENTE DE CONNEXION » S'AFFICHAIT ALORS QU'ON ÉTAIT CONNECTÉ (user,
/// 30/10/2026). L'ancienne règle était « temps réel connecté ET aucune requête
/// HTTP en échec » : la moindre requête refusée — un jeton expiré, une erreur
/// du serveur — allumait le bandeau, que seul un sondage réussi éteignait.
///
/// 🔴 LA RÈGLE, DÉSORMAIS :
///  - connexion temps réel établie → en ligne, quoi qu'aient donné les requêtes
///    HTTP (le ping du [RealtimeClient] détecte lui-même une liaison morte) ;
///  - temps réel coupé → en ligne tant que la dernière requête HTTP a réussi ;
///    la coupure efface la réussite précédente ;
///  - « hors ligne » n'est annoncé qu'après [delaiConfirmation] de coupure
///    continue : une reconnexion d'une seconde n'a pas à faire clignoter
///    l'écran.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService(
    this._rt, {
    this.delaiConfirmation = const Duration(seconds: 3),
  }) {
    _wsConnecte = _rt.connected;
    _rt.addListener(_surTempsReel);
    _reevaluer();
  }

  final RealtimeClient _rt;

  /// Durée de coupure continue avant d'annoncer « hors ligne ».
  final Duration delaiConfirmation;

  bool _wsConnecte = false;
  bool _httpOk = false;
  bool _horsLigne = false;
  Timer? _attente;

  bool get isOnline => !_horsLigne;
  bool get isOffline => _horsLigne;

  bool get _brutHorsLigne => !_wsConnecte && !_httpOk;

  void _surTempsReel() {
    final connecte = _rt.connected;
    if (connecte == _wsConnecte) return;
    _wsConnecte = connecte;
    // La liaison vient de tomber : une réussite HTTP d'avant ne prouve plus rien.
    if (!connecte) _httpOk = false;
    _reevaluer();
  }

  void _reevaluer() {
    if (!_brutHorsLigne) {
      _attente?.cancel();
      _attente = null;
      if (_horsLigne) {
        _horsLigne = false;
        notifyListeners();
      }
      return;
    }
    if (_horsLigne || _attente != null) return;
    _attente = Timer(delaiConfirmation, () {
      _attente = null;
      if (_brutHorsLigne && !_horsLigne) {
        _horsLigne = true;
        notifyListeners();
      }
    });
  }

  /// Une requête HTTP a échoué. Ne compte que si le temps réel est coupé.
  void markHttpFailed() {
    _httpOk = false;
    _reevaluer();
  }

  /// Une requête HTTP a réussi → on est effectivement en ligne.
  void markHttpSucceeded() {
    _httpOk = true;
    _reevaluer();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _rt.removeListener(_surTempsReel);
    super.dispose();
  }
}
