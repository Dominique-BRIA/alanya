import 'package:flutter/foundation.dart';

import 'realtime_client.dart';

/// Observe l'état de connectivité (online/offline) de l'app.
///
/// On s'appuie sur le [RealtimeClient] comme source de vérité principale :
///  - Si la WS est connectée → online
///  - Si elle n'arrive pas à se reconnecter → offline (probablement pas de réseau)
///
/// Optionnellement, on peut aussi marquer offline explicitement quand une
/// requête HTTP échoue avec un SocketException.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService(this._rt) {
    _rt.addListener(_onRealtimeChange);
    _isOnline = _rt.connected;
  }

  final RealtimeClient _rt;
  bool _isOnline = false;
  bool _httpFailed = false;

  bool get isOnline => _isOnline && !_httpFailed;
  bool get isOffline => !isOnline;

  void _onRealtimeChange() {
    final newState = _rt.connected;
    if (newState != _isOnline) {
      _isOnline = newState;
      // Un reconnect WS remet à zéro le drapeau HTTP.
      if (newState) _httpFailed = false;
      notifyListeners();
    }
  }

  /// Appelé par les repositories quand une requête HTTP échoue avec un
  /// SocketException. Bascule l'app en "offline" même si la WS croit encore
  /// être connectée (souvent le TCP idle sur mobile).
  void markHttpFailed() {
    if (!_httpFailed) {
      _httpFailed = true;
      notifyListeners();
    }
  }

  /// Appelé quand une requête HTTP réussit → on est effectivement online.
  void markHttpSucceeded() {
    if (_httpFailed || !_isOnline) {
      _httpFailed = false;
      _isOnline = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _rt.removeListener(_onRealtimeChange);
    super.dispose();
  }
}
