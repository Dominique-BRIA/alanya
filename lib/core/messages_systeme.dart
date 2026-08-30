import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// MESSAGES SYSTÈME — ceux que le serveur dépose dans une conversation et qui
/// s'affichent centrés, sans appartenir à personne.
///
/// 🔴 LE MOBILE AFFICHAIT LEUR JSON BRUT (signalé sur device le 30/08/2026 :
/// « le message json qui s'affiche dans le groupe n'est pas formaté »). Le
/// serveur enregistre `{"code":"member_added","target":"…","actor":"…"}` et
/// attend du client qu'il compose la phrase ; le web le faisait
/// (`src/i18n/messages-systeme.ts`), le mobile affichait `m.content` tel quel.
///
/// **Ce fichier est le MIROIR Dart du module web**, et doit le rester : mêmes
/// codes, mêmes paramètres, mêmes replis. Un code ajouté d'un seul côté
/// donnerait deux comportements pour un même message en base.
///
/// Pourquoi le texte n'est pas figé en base, côté serveur :
///   - chacun lit l'application dans SA langue, et une phrase enregistrée en
///     français resterait française pour tout le monde ;
///   - certains avis ne disent pas la même chose selon qui lit — celui qui a
///     bloqué ne lit pas la même phrase que celui qui a été bloqué.

/// Lit la charge d'un message système, ou `null` si ce n'en est pas une.
///
/// ⚠️ Un message système ANCIEN porte une phrase en clair, pas du JSON : c'est
/// le cas de « Messages éphémères activés · 24 heures », déposé par le serveur
/// WebSocket. Ne pas le reconnaître ici est normal — l'appelant l'affiche alors
/// tel quel, ce qui reste juste.
Map<String, dynamic>? _lireCharge(String? contenu) {
  if (contenu == null) return null;
  final debut = contenu.trimLeft();
  if (!debut.startsWith("{")) return null;
  try {
    final objet = jsonDecode(debut);
    if (objet is! Map) return null;
    final carte = Map<String, dynamic>.from(objet);
    return carte["code"] is String ? carte : null;
  } catch (_) {
    // Un contenu qui commence par « { » sans être du JSON valide n'est pas une
    // charge : on le rend à l'appelant, qui l'affichera tel quel.
    return null;
  }
}

String _texte(dynamic valeur) => valeur is String ? valeur : "";

/// Compose la phrase à afficher pour un message système.
///
/// [monId] sert aux avis dont la formulation dépend du lecteur.
///
/// Renvoie une chaîne VIDE pour un code inconnu — un client plus ancien que le
/// serveur. C'est délibéré et c'est la règle du web : on n'invente pas de
/// phrase, et on ne montre surtout pas le JSON. L'appelant masque la bulle.
String composerMessageSysteme(
  BuildContext context,
  String? contenu,
  String? monId,
) {
  final charge = _lireCharge(contenu);
  // Pas une charge : une phrase en clair d'une version antérieure. Mieux vaut
  // une phrase figée dans une seule langue qu'une bulle vide.
  if (charge == null) return contenu ?? "";

  switch (charge["code"] as String) {
    case "blocked_notice":
      // Le même message, lu des deux côtés, ne dit pas la même chose.
      final jeSuisLeBloqueur =
          monId != null && _texte(charge["blockerId"]) == monId;
      final modele = tr(context,
          jeSuisLeBloqueur ? 'system_you_blocked' : 'system_you_were_blocked');
      final nom = jeSuisLeBloqueur
          ? _texte(charge["blockedName"])
          : _texte(charge["blockerName"]);
      return modele.replaceFirst("{name}", nom);

    case "member_added":
      return tr(context, 'system_member_added')
          .replaceFirst("{target}", _texte(charge["target"]))
          .replaceFirst("{actor}", _texte(charge["actor"]));

    case "member_removed":
      return tr(context, 'system_member_removed')
          .replaceFirst("{target}", _texte(charge["target"]))
          .replaceFirst("{actor}", _texte(charge["actor"]));

    case "member_left":
      // Un départ volontaire ne nomme personne d'autre : pas d'auteur.
      return tr(context, 'system_member_left')
          .replaceFirst("{target}", _texte(charge["target"]));

    default:
      return "";
  }
}

/// Aperçu d'un message système pour la LISTE DES DISCUSSIONS.
///
/// 🔴 La liste lit `conversation.lastMessage`, où le serveur recopie la même
/// charge JSON. Sans passer par ici, l'aperçu d'un groupe affiche
/// `{"code":"member_added",…}` — le même défaut qu'en haut, au même endroit que
/// l'utilisateur regarde le plus souvent.
///
/// Un code inconnu rend une chaîne vide, comme dans le fil : la conversation
/// montre alors un aperçu vide plutôt qu'une accolade.
String apercuMessageSysteme(
  BuildContext context,
  String? contenu,
  String? monId,
) =>
    composerMessageSysteme(context, contenu, monId);
