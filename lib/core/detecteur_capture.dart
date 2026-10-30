import 'package:flutter/services.dart';

/// « X A FAIT UNE CAPTURE D'ÉCRAN » (29/10/2026, demande du user).
///
/// Android prévient (`DetecteurCapture.kt`, canal `alanya/capture`) qu'une
/// capture vient d'être prise, application au premier plan. Reste à savoir
/// DANS QUELLE CONVERSATION : c'est cette pile qui le dit.
///
/// 🔴 UNE PILE, PAS UNE VARIABLE. Chaque écran de conversation s'y inscrit à
/// l'ouverture et s'en retire à la fermeture. Une photo, une vidéo ou un
/// document ouvert DEPUIS la conversation s'empile par-dessus elle sans la
/// fermer : la capture lui est donc attribuée — c'est ce que le user voulait.
/// Une conversation ouverte depuis une autre (un transfert, par exemple) passe
/// au sommet, puis lui rend la place en se fermant.
///
/// ⚠️ Hors de toute conversation, une capture n'est signalée à personne.
class DetecteurCapture {
  DetecteurCapture._();
  static final instance = DetecteurCapture._();

  static const _canal = MethodChannel('alanya/capture');

  final _pile = <_Inscription>[];
  bool _ecoute = false;

  /// Inscrit une conversation ouverte. [signaler] annonce la capture au
  /// serveur ; le jeton rendu sert à se retirer.
  Object entrer(String convId, Future<void> Function() signaler) {
    _ecouter();
    final i = _Inscription(convId, signaler);
    _pile.add(i);
    return i;
  }

  /// Retire l'inscription rendue par [entrer].
  void sortir(Object jeton) => _pile.remove(jeton);

  void _ecouter() {
    if (_ecoute) return;
    _ecoute = true;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method != 'capture' || _pile.isEmpty) return;
      try {
        await _pile.last.signaler();
      } catch (_) {
        // Réseau : l'avis se perd, la capture, elle, est faite. Rien à rattraper.
      }
    });
  }
}

class _Inscription {
  _Inscription(this.convId, this.signaler);
  final String convId;
  final Future<void> Function() signaler;
}
