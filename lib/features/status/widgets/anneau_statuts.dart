import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Anneau segmenté autour d'un avatar : un arc par statut, façon WhatsApp.
///
/// L'anneau porte à lui seul deux informations que la liste ne dit plus en
/// toutes lettres : **combien** de statuts la personne a publiés, et **lesquels**
/// restent à voir (un arc par statut, teinté selon qu'il est vu ou non).
///
/// Un seul statut donne un cercle plein : découper un cercle en un segment
/// laisserait une entaille inexplicable.
class AnneauStatuts extends StatelessWidget {
  const AnneauStatuts({
    super.key,
    required this.vus,
    required this.couleurNonVu,
    required this.couleurVu,
    required this.child,
    this.epaisseur = 2.5,
    this.ecart = 3,
  });

  /// Un booléen par statut, dans l'ordre d'affichage : `true` = déjà vu.
  final List<bool> vus;
  final Color couleurNonVu;
  final Color couleurVu;

  /// L'avatar. Il est mis en retrait pour laisser la place à l'anneau.
  final Widget child;

  /// Épaisseur du trait de l'anneau.
  final double epaisseur;

  /// Espace laissé entre l'anneau et l'avatar.
  final double ecart;

  @override
  Widget build(BuildContext context) {
    if (vus.isEmpty) return child;
    return CustomPaint(
      // `painter` et non `foregroundPainter` : l'anneau se dessine SOUS l'enfant,
      // donc il ne peut jamais mordre sur la photo.
      painter: _PeintreAnneau(
        vus: vus,
        couleurNonVu: couleurNonVu,
        couleurVu: couleurVu,
        epaisseur: epaisseur,
      ),
      child: Padding(padding: EdgeInsets.all(epaisseur + ecart), child: child),
    );
  }
}

/// Écart maximal entre deux arcs, en radians (~7°).
const double _ecartMax = 0.12;

/// Un arc de l'anneau : son angle de départ et son balayage, en radians.
typedef SegmentAnneau = ({double debut, double balayage});

/// Découpe l'anneau en [nombre] arcs égaux, séparés par un écart.
///
/// Sortie PURE, sans écran ni canevas : c'est ce qui rend la géométrie
/// vérifiable — voir `test/anneau_statuts_test.dart`.
///
/// Deux propriétés la gouvernent :
/// - un seul statut donne un cercle entier, sans entaille ;
/// - l'écart **rétrécit** quand les arcs se multiplient (il ne dépasse jamais
///   le tiers du pas), sinon une vingtaine de statuts ne laisserait plus rien
///   à dessiner et l'anneau disparaîtrait.
///
/// Les arcs partent du haut du cercle, comme WhatsApp : le premier est celui
/// que la visionneuse ouvrira en premier.
List<SegmentAnneau> segmentsAnneau(int nombre) {
  if (nombre <= 0) return const [];
  const depart = -math.pi / 2;
  if (nombre == 1) {
    return const [(debut: depart, balayage: 2 * math.pi)];
  }
  final pas = 2 * math.pi / nombre;
  final ecart = math.min(_ecartMax, pas / 3);
  return List.generate(
    nombre,
    (i) => (debut: depart + ecart / 2 + i * pas, balayage: pas - ecart),
  );
}

class _PeintreAnneau extends CustomPainter {
  const _PeintreAnneau({
    required this.vus,
    required this.couleurNonVu,
    required this.couleurVu,
    required this.epaisseur,
  });

  final List<bool> vus;
  final Color couleurNonVu;
  final Color couleurVu;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    final segments = segmentsAnneau(vus.length);
    if (segments.isEmpty) return;

    final centre = Offset(size.width / 2, size.height / 2);
    // On retire une demi-épaisseur : un trait est centré sur son tracé, sinon
    // sa moitié extérieure déborderait de la zone allouée et serait rognée.
    final rayon = (size.shortestSide - epaisseur) / 2;
    if (rayon <= 0) return;

    final rect = Rect.fromCircle(center: centre, radius: rayon);
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      // Bouts francs : un bout arrondi ajoute une demi-épaisseur à chaque
      // extrémité et referme l'écart dès que les statuts se multiplient.
      ..strokeCap = StrokeCap.butt;

    for (var i = 0; i < segments.length; i++) {
      trait.color = vus[i] ? couleurVu : couleurNonVu;
      canvas.drawArc(
        rect,
        segments[i].debut,
        segments[i].balayage,
        false,
        trait,
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreAnneau ancien) =>
      ancien.epaisseur != epaisseur ||
      ancien.couleurNonVu != couleurNonVu ||
      ancien.couleurVu != couleurVu ||
      !listEquals(ancien.vus, vus);
}
