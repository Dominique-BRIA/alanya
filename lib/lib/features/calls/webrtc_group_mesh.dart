import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'webrtc_peer_session.dart';

/// Mesh WebRTC : une connexion par participant distant, flux local partagé.
class WebrtcGroupMesh {
  WebrtcGroupMesh({
    required this.myUserId,
    required this.isVideo,
    required this.iceServers,
    required this.onSendSignal,
    required this.onUpdated,
  });

  final String myUserId;
  final bool isVideo;
  final List<Map<String, dynamic>> iceServers;
  final void Function(String peerId, Map<String, dynamic> signal) onSendSignal;
  final VoidCallback onUpdated;

  MediaStream? _local;
  final Map<String, WebrtcPeerSession> _peers = {};
  final Map<String, List<Map<String, dynamic>>> _pendingByPeer = {};

  MediaStream? get localStream => _local;
  Map<String, MediaStream> get remoteStreams => {
        for (final e in _peers.entries)
          if (e.value.remoteStream != null) e.key: e.value.remoteStream!,
      };
  int get connectedCount => remoteStreams.length;
  Set<String> get peerIds => _peers.keys.toSet();

  static bool shouldOffer(String myId, String peerId) => myId.compareTo(peerId) < 0;

  Future<void> ensureLocal() async {
    _local ??= await navigator.mediaDevices.getUserMedia({
      "audio": true,
      "video": isVideo,
    });
    onUpdated();
  }

  Future<void> connectToPeer(String peerId) async {
    if (peerId == myUserId || _peers.containsKey(peerId)) return;
    await ensureLocal();
    final session = WebrtcPeerSession(
      peerId: peerId,
      isVideo: isVideo,
      isOfferer: shouldOffer(myUserId, peerId),
      localStream: _local!,
      iceServers: iceServers,
      onSendSignal: (sig) => onSendSignal(peerId, sig),
      onUpdated: onUpdated,
    );
    _peers[peerId] = session;
    await session.start();
    final buffered = _pendingByPeer.remove(peerId) ?? [];
    for (final sig in buffered) {
      await session.handleSignal(sig);
    }
  }

  Future<void> handleSignal(String fromPeerId, Map<String, dynamic> signal) async {
    final session = _peers[fromPeerId];
    if (session == null) {
      _pendingByPeer.putIfAbsent(fromPeerId, () => []).add(signal);
      return;
    }
    await session.handleSignal(signal);
  }

  Future<void> removePeer(String peerId) async {
    await _peers.remove(peerId)?.close();
    _pendingByPeer.remove(peerId);
    onUpdated();
  }

  Future<void> close() async {
    for (final s in _peers.values) {
      await s.close();
    }
    _peers.clear();
    _pendingByPeer.clear();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
  }
}
