import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/server_config.dart';
import 'image_octets.dart';
import 'auth_network_image.dart';

/// Interprète la valeur brute de `avatarUrl` telle qu'elle arrive du serveur.
///
/// Trois formes coexistent en base, et c'est voulu — la base est PARTAGÉE avec
/// l'application de l'équipe :
///
///   `/api/media/<id>`        notre forme canonique, écrite par cette app
///   `https://...`            avatars générés (dicebear) des comptes de service
///   `data:image/jpeg;base64` écrits DIRECTEMENT en base par l'app de l'équipe
///
/// Nos écrans ne produisent jamais la troisième — `PATCH /api/account/profile`
/// la refuse par validation — mais ils doivent savoir la LIRE. Sans quoi le
/// test `startsWith("http")` la traite comme un chemin relatif et fabrique une
/// URL absurde du genre `https://alanyavox.com/apidata:image/jpeg;base64,...`,
/// qui échoue : ces comptes s'affichaient avec une image cassée.
class AvatarSource {
  const AvatarSource._({this.url, this.bytes});

  /// URL absolue, à charger avec le jeton via [AuthNetworkImage].
  final String? url;

  /// Image déjà présente en base, décodée ici même — aucun appel réseau.
  final Uint8List? bytes;

  bool get estVide => url == null && bytes == null;

  factory AvatarSource.depuis(String? brut) {
    final valeur = brut?.trim();
    if (valeur == null || valeur.isEmpty) return const AvatarSource._();

    if (valeur.startsWith("data:")) {
      final virgule = valeur.indexOf(',');
      if (virgule < 0) return const AvatarSource._();
      try {
        // Les retours à la ligne sont tolérés dans le base64 transporté, mais
        // pas par le décodeur de Dart.
        final utile =
            valeur.substring(virgule + 1).replaceAll(RegExp(r'\s'), '');
        return AvatarSource._(bytes: base64Decode(utile));
      } catch (_) {
        // Valeur tronquée ou non-base64 (`data:image/svg+xml,<svg…`) : on
        // retombe sur l'initiale, comme pour un avatar absent. Un écran ne doit
        // jamais casser à cause d'une donnée écrite par une autre application.
        return const AvatarSource._();
      }
    }

    if (valeur.startsWith("http")) return AvatarSource._(url: valeur);

    // Chemin relatif au serveur. La barre de tête est rétablie si elle manque :
    // sans elle, la concaténation donnerait `https://alanyavox.comapi/media/…`.
    final chemin = valeur.startsWith("/") ? valeur : "/$valeur";
    return AvatarSource._(url: "${ServerConfig.apiBase}$chemin");
  }

  /// Le widget d'image, ou `null` s'il n'y a rien à afficher — l'appelant
  /// montre alors l'initiale. [token] n'est nécessaire que pour les URL :
  /// une image déjà en base s'affiche même avant que le jeton soit lu.
  Widget? image({
    double? width,
    double? height,
    String? token,
    BoxFit fit = BoxFit.cover,
  }) {
    if (bytes != null) {
      // Passe par le rendu commun : la valeur peut etre un SVG encode en
      // base64, que `Image.memory` ne saurait pas afficher.
      return imageDepuisOctets(bytes!, width: width, height: height, fit: fit);
    }
    if (url != null && token != null) {
      return AuthNetworkImage(
        url: url!,
        token: token,
        width: width,
        height: height,
        fit: fit,
      );
    }
    return null;
  }
}
