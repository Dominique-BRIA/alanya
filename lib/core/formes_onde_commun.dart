import 'dart:math';

/// Nombre de barres d'une forme d'onde de message vocal (comme Talky).
const int barresFormeOnde = 56;

/// Des barres DÉTERMINISTES, quand l'extraction échoue ou n'est pas possible
/// (web, fichier pas encore là) : jamais vide, et toujours la même forme pour
/// le même message — un vocal ne change pas d'allure d'un affichage à l'autre.
List<double> formeOndeDeRepli(String graine, int dureeSecondes,
    {int barres = barresFormeOnde}) {
  final s = Object.hash(graine, dureeSecondes);
  final hasard = Random(s);
  return List<double>.generate(barres, (i) {
    final t = i / barres;
    final onde = 0.35 + 0.45 * sin(t * pi * 5 + (s % 7));
    final bruit = hasard.nextDouble() * 0.2;
    return (onde + bruit).clamp(0.08, 1.0);
  });
}
