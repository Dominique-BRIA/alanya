import 'package:flutter_webrtc/flutter_webrtc.dart';

/// CE QUE LES ÉCRANS D'APPEL ET DE RÉUNION ATTENDENT D'UN MOTEUR MÉDIA
/// (07/11/2026).
///
/// Deux moteurs l'implémentent :
///  - [WebrtcGroupMesh], le système d'origine : une connexion par
///    participant, chacune négociée de pair à pair par le socket ;
///  - [WebrtcSfu], le SFU de Cloudflare : UNE connexion, vers Cloudflare, où
///    l'on publie ses pistes une fois et d'où l'on reçoit celles des autres.
///
/// Le moteur d'un appel est fixé par le serveur à sa création (`moteur` :
/// `mesh` ou `sfu`), selon le réglage de la console. Le tête-à-tête est
/// toujours en mesh. Les contrôleurs ne voient que cette interface : le choix
/// ne change rien à leur logique.
abstract class MoteurMedia {
  bool get isVideo;

  MediaStream? get localStream;

  /// Les flux reçus, par participant.
  Map<String, MediaStream> get remoteStreams;
  int get connectedCount;
  Set<String> get peerIds;

  bool get micEnabled;
  bool get cameraEnabled;
  bool get aUneCamera;

  /// Une liaison au moins est-elle dégradée ? → « Connexion faible ».
  bool get connexionFaible;

  /// La caméra de [peerId] est-elle allumée ?
  bool cameraDistanteActive(String peerId);

  Future<void> ensureLocal();
  void setMic(bool on);
  void setCamera(bool on);
  Future<void> switchCamera();
  void envoyerEtatCamera(bool active);
  void suspendreVideoLocale(bool suspendue);
  Future<void> rafraichirVideoLocale();
  Future<void> passerEnVideo({required bool camera, bool annoncer = false});

  /// Le réseau du téléphone a changé : relancer les liaisons.
  void relancerLesLiaisons();

  /// [peerId] est dans l'appel. [asOfferer] n'a de sens qu'en mesh.
  Future<void> connectToPeer(String peerId, {required bool asOfferer});

  /// Un signal reçu de [fromPeerId] par le socket.
  Future<void> handleSignal(String fromPeerId, Map<String, dynamic> signal);
  Future<void> removePeer(String peerId);
  Future<void> close();

  /// Le niveau sonore de chacun (0 à 1), pour savoir qui parle : par
  /// participant, et sous [moiCle] pour notre propre micro. `null` : rien à
  /// mesurer pour l'instant.
  Future<Map<String, double>?> niveauxAudio(String moiCle);
}
