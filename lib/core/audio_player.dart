// Barrel export : expose l'état partagé ET l'implémentation adaptée à la plateforme.
// - Sur mobile/desktop : audio_player_io.dart (paquet audioplayers)
// - Sur web            : audio_player_web.dart (dart:html AudioElement)
export 'audio_state.dart';
export 'audio_player_io.dart' if (dart.library.html) 'audio_player_web.dart';
