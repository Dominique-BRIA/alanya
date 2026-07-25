import 'dart:async';

import 'package:flutter/foundation.dart';

import 'realtime_client.dart';

/// Présence (en ligne / dernière connexion) des interlocuteurs, tenue à jour en
/// TEMPS RÉEL par les événements WebSocket `presence` (émis par le serveur à la
/// connexion/déconnexion d'un utilisateur). Remplace le polling : les écrans
/// lisent ici pour un affichage live.
///
/// Repli : si le store ne connaît pas encore un utilisateur, les écrans
/// retombent sur les données REST déjà chargées (ex. liste des conversations).
class PresenceStore extends ChangeNotifier {
  PresenceStore(this._rt) {
    _sub = _rt.events.listen(_onEvent);
  }

  final RealtimeClient _rt;
  StreamSubscription<Map<String, dynamic>>? _sub;

  final Map<String, bool> _online = {};
  final Map<String, DateTime?> _lastSeen = {};

  /// `null` = présence inconnue du store (l'écran utilise son repli REST).
  bool? isOnline(String userId) => _online[userId];
  DateTime? lastSeen(String userId) => _lastSeen[userId];

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'presence') return;
    final uid = e['userId'] as String?;
    if (uid == null) return;
    _online[uid] = (e['isOnline'] as num?)?.toInt() == 1;
    final ls = e['lastSeen'] as String?;
    if (ls != null) _lastSeen[uid] = DateTime.tryParse(ls);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
