/// État de lecture audio, partagé entre le lecteur et l'UI.
///
/// Immutable : chaque changement crée une nouvelle instance (via [copyWith]),
/// ce qui garantit que le [ValueNotifier] notifie correctement ses auditeurs.
class AudioPlaybackState {
  /// URL du média en cours de lecture (null = rien ne joue).
  final String? url;

  /// true si l'audio est en train de jouer, false s'il est en pause/arrêté.
  final bool isPlaying;

  /// Position courante dans le flux audio.
  final Duration position;

  /// Durée totale du média (peut venir du backend ou être détectée à la lecture).
  final Duration? duration;

  const AudioPlaybackState({
    this.url,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration,
  });

  /// Crée une copie avec les champs modifiés (null = inchangé).
  AudioPlaybackState copyWith({
    String? url,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    return AudioPlaybackState(
      url: url ?? this.url,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}
