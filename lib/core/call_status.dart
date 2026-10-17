import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/call_record.dart';
import 'push_service.dart';

/// Formalisme des statuts d'appel.
///
/// ⚠️ LA SOURCE DE VÉRITÉ EST LE SERVEUR. Depuis que `GET /api/calls` renvoie
/// `preciseStatus`, `detail`, `isFailed` et `colorHint` déjà formulés pour le
/// destinataire, ce fichier ne fait plus que les afficher.
///
/// Tout ce qui suit sous le nom de « repli » n'existe que pour un cas : un
/// mobile à jour face à un serveur qui n'a pas encore été déployé. Les champs
/// valent alors nul et l'ancien calcul reprend la main, le temps de la
/// transition. Ce n'est pas une seconde implémentation à maintenir en parallèle
/// — dès que la prod est à jour, plus personne ne devrait passer par là.
///
/// ⚠️ NE PAS y rajouter de règle. Une divergence entre les deux calculs se
/// traduirait par un libellé qui change selon la version du serveur, ce qui est
/// exactement le désordre que ce chantier corrige. Toute évolution du
/// formalisme se fait dans `libelleAppel()` côté backend.
///
/// 🌍 TRADUCTION (≠ règle). Le serveur formule ses libellés en français :
/// `_clesServeur` les associe à leurs équivalents du catalogue l10n, affichés
/// dans la langue de l'app. Un libellé absent de la table s'affiche tel quel,
/// sans interprétation client — la source de vérité du formalisme ne bouge
/// pas d'un iota, seule sa langue d'affichage change.
///
/// Le formalisme, pour mémoire :
///
/// * Appel manqué (Missed) : entrant sans réponse de votre part
/// * Appel rejeté (Declined/Rejected) : entrant refusé volontairement par vous
/// * Appel sans réponse (No Answer) : sortant non décroché par correspondant
/// * Occupé (Busy) : sortant tombe sur ligne occupée
/// * Appel refusé : sortant que le correspondant a rejeté
/// * Appel entrant/sortant : appel répondu (avec durée)
///
/// Nuances :
/// A appelle B, B ne décroche pas => chez A "Appel sans réponse", chez B "Appel manqué"
/// B rejette => chez A "Appel refusé", chez B "Appel rejeté"

class CallStatusFormalisme {
  /// Traduit depuis un contexte statique, sans BuildContext : les listes qui
  /// affichent ce formalisme ne le transportent pas. Repli français si le
  /// navigateur de l'application n'est pas monté — même logique que
  /// [CallUiNative._libelle].
  static String _traduire(String cle, String repliFrancais,
      [Map<String, String>? params]) {
    final ctx = PushService.navigatorKey.currentContext;
    if (ctx == null) return repliFrancais;
    try {
      return tr(ctx, cle, params);
    } catch (_) {
      return repliFrancais;
    }
  }

  /// Libellés formulés par le serveur (en français) → clés du catalogue l10n.
  /// Couvre `preciseStatus` ET `detail` — voir l'avertissement 🌍 en tête de
  /// fichier : c'est une table de traduction, pas une règle.
  static const Map<String, String> _clesServeur = {
    // preciseStatus
    'Appel manqué': 'missed_call',
    'Appel rejeté': 'call_declined_in',
    'Appel sans réponse': 'call_no_answer',
    'Appel refusé': 'call_refused_out',
    'Occupé': 'call_busy',
    'Appel entrant': 'call_incoming_word',
    'Appel sortant': 'call_outgoing',
    'En cours': 'call_ongoing_short',
    // detail
    'Manqué': 'call_missed_short',
    'Rejeté': 'call_rejected_short',
    'Refusé': 'call_refused_short',
    'Sans réponse': 'call_no_answer_short',
    'Répondu': 'call_answered_short',
  };

  /// Traduit un libellé venu du serveur, ou le renvoie tel quel s'il n'est
  /// pas répertorié — jamais d'interprétation côté client.
  static String _traduireDuServeur(String libelle) {
    final cle = _clesServeur[libelle];
    if (cle == null) return libelle;
    return _traduire(cle, libelle);
  }

  /// Libellé précis pour la **liste d'appels** + **aperçu conversations**
  /// Ex: "Appel manqué", "Appel rejeté", "Appel sans réponse", "Appel refusé", "Occupé", "Appel entrant", "Appel sortant"
  static String preciseLabel(CallRecord c) {
    final duServeur = c.preciseStatus;
    if (duServeur != null && duServeur.isNotEmpty) {
      return _traduireDuServeur(duServeur);
    }
    return _preciseLabelRepli(c);
  }

  /// Repli — voir l'avertissement en tête de fichier.
  static String _preciseLabelRepli(CallRecord c) {
    final s = c.status;
    final outgoing = c.isOutgoing;

    switch (s) {
      case "MISSED":
        // Backend dit MISSED : déjà nuancé par isOutgoing côté serveur
        return outgoing
            ? _traduire('call_no_answer', "Appel sans réponse")
            : _traduire('missed_call', "Appel manqué");
      case "NO_ANSWER":
        return outgoing
            ? _traduire('call_no_answer', "Appel sans réponse")
            : _traduire('missed_call', "Appel manqué");
      case "REJECTED":
      case "DECLINED":
        // Rejeté par moi (entrant) vs refusé par l'autre (sortant)
        return outgoing
            ? _traduire('call_refused_out', "Appel refusé")
            : _traduire('call_declined_in', "Appel rejeté");
      case "BUSY":
        return _traduire('call_busy', "Occupé");
      case "ENDED":
        if (c.durationSec != null && c.durationSec! > 0) {
          return outgoing
              ? _traduire('call_outgoing', "Appel sortant")
              : _traduire('call_incoming_word', "Appel entrant");
        } else {
          // Sans durée => pas décroché
          return outgoing
              ? _traduire('call_no_answer', "Appel sans réponse")
              : _traduire('missed_call', "Appel manqué");
        }
      case "RINGING":
        return outgoing
            ? _traduire('call_outgoing', "Appel sortant")
            : _traduire('call_incoming_word', "Appel entrant");
      case "ONGOING":
        return _traduire('call_ongoing_short', "En cours");
      default:
        return s;
    }
  }

  /// Titre pour bulle dans fil discussion : "Appel vocal entrant", "Appel vocal sortant", "Appel vidéo entrant" etc.
  static String titleInChat(CallRecord c) {
    final typeLabel = c.type == "VIDEO"
        ? _traduire('video_call', "Appel vidéo")
        : _traduire('call_voice_word', "Appel vocal");
    if (c.isGroup) {
      return _traduire(
          'call_title_group', "$typeLabel de groupe", {'type': typeLabel});
    }
    return c.isOutgoing
        ? _traduire(
            'call_title_out', "$typeLabel sortant", {'type': typeLabel})
        : _traduire(
            'call_title_in', "$typeLabel entrant", {'type': typeLabel});
  }

  /// Détail court pour bulle chat : "Manqué", "Rejeté", "Refusé", "Sans réponse", "Occupé", "Répondu"
  /// On garde la nuance Refusé vs Rejeté dans la bulle aussi.
  static String detailInChat(CallRecord c) {
    final duServeur = c.detail;
    if (duServeur != null && duServeur.isNotEmpty) {
      return _traduireDuServeur(duServeur);
    }
    return _detailRepli(c);
  }

  /// Repli — voir l'avertissement en tête de fichier.
  static String _detailRepli(CallRecord c) {
    final s = c.status;
    final outgoing = c.isOutgoing;
    final hasDuration = c.durationSec != null && c.durationSec! > 0;

    if (s == "BUSY") return _traduire('call_busy', "Occupé");
    if (s == "REJECTED" || s == "DECLINED") {
      return outgoing
          ? _traduire('call_refused_short', "Refusé")
          : _traduire('call_rejected_short', "Rejeté");
    }
    if (s == "MISSED" || s == "NO_ANSWER") {
      // image montre "Sans réponse" même pour entrant
      return _traduire('call_no_answer_short', "Sans réponse");
    }
    if (s == "ENDED") {
      if (hasDuration) return _traduire('call_answered_short', "Répondu");
      return _traduire('call_no_answer_short', "Sans réponse");
    }
    if (s == "RINGING" || s == "ONGOING") {
      return _traduire('call_ongoing_short', "En cours");
    }
    return s;
  }

  /// Libellé long combiné pour aperçu type WhatsApp dans tile conversation : utilise preciseLabel
  /// Mais pour respecter image, on pourrait garder titleInChat + detail
  static String combinedForConversationTile(CallRecord c) {
    // Ex: "Appel vocal entrant Rejeté · 15:12" – on utilise title + detail
    // Pour la liste conversations, on affiche preciseLabel qui est déjà clair
    return preciseLabel(c);
  }

  static IconData iconFor(CallRecord c) {
    // L'icône reste choisie ici : c'est de la présentation, le serveur n'a pas
    // à connaître le jeu d'icônes de Material. Mais l'ÉCHEC, lui, vient de lui
    // quand il le dit — un entrant raté prend la flèche barrée.
    final echec = c.isFailed;
    if (echec != null) {
      if (echec) return c.isOutgoing ? Icons.call_made : Icons.call_missed;
      return c.isOutgoing ? Icons.call_made : Icons.call_received;
    }
    return _iconRepli(c);
  }

  /// Repli — voir l'avertissement en tête de fichier.
  static IconData _iconRepli(CallRecord c) {
    final s = c.status;
    final outgoing = c.isOutgoing;
    final hasDuration = c.durationSec != null && c.durationSec! > 0;

    if (s == "MISSED" || s == "NO_ANSWER") {
      return outgoing ? Icons.call_made : Icons.call_missed;
    }
    if (s == "REJECTED" || s == "DECLINED") {
      // entrant rejeté = call_received barré visuellement, mais on garde call_received/call_made pour flèche
      return outgoing ? Icons.call_made : Icons.call_received;
    }
    if (s == "BUSY") return Icons.block;
    if (s == "ENDED") {
      if (hasDuration) return outgoing ? Icons.call_made : Icons.call_received;
      return outgoing ? Icons.call_made : Icons.call_missed;
    }
    return outgoing ? Icons.call_made : Icons.call_received;
  }

  static Color colorFor(CallRecord c, {required Color danger, required Color positive, Color incomingAnswered = const Color(0xFF2196F3), Color muted = Colors.black54}) {
    // `colorHint` nomme une INTENTION (« danger »), pas une couleur : le
    // serveur ignore tout des quatre thèmes, et c'est l'appelant qui fournit
    // les teintes correspondantes.
    switch (c.colorHint) {
      case "danger":
        return danger;
      case "positive":
        return positive;
      case "info":
        return incomingAnswered;
      case "neutral":
        return muted;
    }
    return _colorRepli(c,
        danger: danger, positive: positive, incomingAnswered: incomingAnswered);
  }

  /// Repli — voir l'avertissement en tête de fichier.
  static Color _colorRepli(CallRecord c, {required Color danger, required Color positive, required Color incomingAnswered}) {
    final s = c.status;
    final hasDuration = c.durationSec != null && c.durationSec! > 0;

    final isFailed = s == "MISSED" ||
        s == "NO_ANSWER" ||
        s == "REJECTED" ||
        s == "DECLINED" ||
        s == "BUSY" ||
        (s == "ENDED" && !hasDuration);

    if (isFailed) return danger; // rouge = manqué/rejeté/sans réponse/occupé/refusé
    // Réussi
    if (c.isOutgoing) return positive; // vert = sortant réussi
    return incomingAnswered; // bleu = entrant réussi
  }

  static String formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}";
  }

  static String formatTimeShort(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(l.hour)}:${two(l.minute)}";
  }

  static String formatDuration(int? sec) {
    if (sec == null || sec <= 0) return "";
    final m = sec ~/ 60;
    final s = sec % 60;
    return "${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}";
  }

  static List<CallRecord> sortAndLimit20(List<CallRecord> calls) {
    final sorted = List<CallRecord>.from(calls);
    sorted.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (sorted.length > 20) return sorted.take(20).toList();
    return sorted;
  }
}
