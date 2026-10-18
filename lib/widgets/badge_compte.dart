import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/images_badges.dart';
import '../models/badge_compte.dart';

/// Dessine le badge envoyé par le serveur à côté d'un nom — et rien d'autre.
///
/// L'image et le libellé viennent de la charge (`badge`) : les changer se fait
/// depuis la console, sans nouvelle version de l'application.
///
/// 🔴 LE BADGE NE DISPARAÎT JAMAIS (user, 18/10/2026) :
/// 1. l'image du TÉLÉPHONE d'abord (`ImagesBadges`) — ou, tant qu'elle n'y est
///    pas, l'image EMBARQUÉE du type (`BadgeCompte.imageEmbarquee`) ;
/// 2. l'image du serveur la remplace dès qu'elle est là ;
/// 3. image du serveur introuvable ou illisible : on revient à l'embarquée.
/// Seul un type inconnu de l'application, sans image du serveur, ne montre
/// rien — le nom reste lisible.
class BadgeCompteWidget extends StatefulWidget {
  const BadgeCompteWidget(this.badge, {super.key, this.taille = 16});

  final BadgeCompte badge;
  final double taille;

  @override
  State<BadgeCompteWidget> createState() => _BadgeCompteWidgetState();
}

class _BadgeCompteWidgetState extends State<BadgeCompteWidget> {
  Uint8List? _octets;
  bool _introuvable = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(covariant BadgeCompteWidget ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.badge.image != widget.badge.image) _charger();
  }

  void _charger() {
    final url = widget.badge.image;
    _introuvable = false;
    if (url.isEmpty) {
      // Badge par défaut (fil officiel sans badge du serveur) : l'embarquée.
      _octets = null;
      _introuvable = true;
      return;
    }
    _octets = ImagesBadges.enMemoire(url);
    if (_octets != null) {
      // Déjà là : on profite de la lecture pour la revérification de session.
      ImagesBadges.lire(url);
      return;
    }
    ImagesBadges.lire(url).then((octets) {
      if (!mounted || widget.badge.image != url) return;
      setState(() {
        _octets = octets;
        _introuvable = octets == null;
      });
    });
  }

  bool get _estSvg =>
      widget.badge.image.toLowerCase().split('?').first.endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final t = widget.taille;
    final embarquee = widget.badge.imageEmbarquee;
    // Le repli de toutes les situations : l'image embarquée si le type en a
    // une, sinon une place vide (le temps de la première lecture) ou rien.
    Widget repli({required bool enAttente}) => embarquee != null
        ? Image.asset(embarquee,
            width: t, height: t, filterQuality: FilterQuality.medium)
        : SizedBox(width: enAttente ? t : 0, height: t);

    final octets = _octets;
    final Widget image;
    if (octets != null) {
      image = _estSvg
          ? SvgPicture.memory(octets,
              width: t,
              height: t,
              placeholderBuilder: (_) => repli(enAttente: false))
          : Image.memory(octets,
              width: t,
              height: t,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => repli(enAttente: false));
    } else if (_introuvable && embarquee == null) {
      return const SizedBox.shrink();
    } else {
      image = repli(enAttente: !_introuvable);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: widget.badge.libelle.isEmpty
          ? image
          : Tooltip(message: widget.badge.libelle, child: image),
    );
  }
}
