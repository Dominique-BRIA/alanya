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
/// 🔴 L'IMAGE VIENT DU TÉLÉPHONE D'ABORD (`ImagesBadges`) : le badge ne
/// disparaît plus hors ligne, et ne surgit plus au milieu de la ligne une
/// seconde après le nom. Sa place est réservée pendant la toute première
/// lecture. Image introuvable partout : rien ne s'affiche, le nom reste
/// lisible.
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
    _octets = ImagesBadges.enMemoire(url);
    _introuvable = false;
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
    final rien = SizedBox(width: 0, height: t);
    final octets = _octets;
    final Widget image;
    if (octets != null) {
      image = _estSvg
          ? SvgPicture.memory(octets, width: t, height: t)
          : Image.memory(octets,
              width: t,
              height: t,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => rien);
    } else if (_introuvable) {
      return const SizedBox.shrink();
    } else {
      // Première lecture en cours : la place est tenue, le nom ne bouge pas.
      image = SizedBox(width: t, height: t);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: widget.badge.libelle.isEmpty
          ? image
          : Tooltip(message: widget.badge.libelle, child: image),
    );
  }
}
