// Barrel : la forme d'onde des messages vocaux.
// - Android / iOS : extraite du fichier (`audio_waveforms`)
// - Web           : barres déterministes
export 'formes_onde_commun.dart';
export 'formes_onde_io.dart' if (dart.library.html) 'formes_onde_web.dart';
