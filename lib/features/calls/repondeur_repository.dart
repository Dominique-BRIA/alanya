import '../../core/api_client.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../core/authed_api.dart';

/// L'accueil d'un correspondant, tel que l'appelant a le droit de l'entendre.
///
/// ⚠️ [url] EST RELATIVE (`/api/media/<id>`) et la route des médias exige un
/// jeton, que le lecteur audio ne sait pas joindre en en-tête. La rendre
/// jouable est le travail de l'appelant — même règle que les sonneries de
/// liste, et pour la même raison.
class AccueilRepondeur {
  const AccueilRepondeur({
    required this.mediaId,
    required this.url,
    required this.absence,
  });

  final String mediaId;
  final String url;

  /// Vrai quand le correspondant a posé une ABSENCE, et non seulement allumé
  /// son répondeur. La nuance se dit à l'écran : « absent » plutôt que « n'a
  /// pas répondu ».
  final bool absence;

  static AccueilRepondeur? depuisJson(Map<String, dynamic> j) {
    final media = j["accueil"];
    if (media is! Map) return null;
    final id = media["id"]?.toString();
    final url = media["url"]?.toString();
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;
    return AccueilRepondeur(
      mediaId: id,
      url: url,
      absence: j["absence"] == true,
    );
  }
}

/// Le répondeur, vu par l'APPELANT.
///
/// ⚠️ Le contrat vit côté serveur (`src/app/api/repondeur/route.ts` et
/// `src/app/api/calls/[id]/voicemail/route.ts`). Ce dépôt ne fait que le
/// traduire en Dart, il n'ajoute aucune règle — en particulier, il ne juge
/// jamais lui-même si un appel « mérite » un répondeur : c'est le serveur qui
/// répond 404, et c'est tant mieux, la règle y est écrite une seule fois.
class RepondeurRepository {
  RepondeurRepository(this._api);
  final AuthedApi _api;

  /// L'accueil du correspondant pour CET appel, ou `null` s'il n'y en a pas.
  ///
  /// 🔴 UN 404 N'EST PAS UNE PANNE, c'est la réponse normale : pas de
  /// répondeur, appel décroché, appel trop ancien, appel de groupe, ou appel
  /// que je n'ai pas passé. Le serveur répond volontairement 404 plutôt que
  /// 403 — distinguer les deux apprendrait à un curieux que le compte existe et
  /// qu'il a un accueil.
  ///
  /// ⚠️ TOUTE AUTRE ERREUR REND AUSSI `null`. Ne pas proposer le répondeur est
  /// un repli acceptable ; faire remonter une exception dans la fin d'un appel
  /// ne l'est pas.
  Future<AccueilRepondeur?> accueilDeLAppel(String callId) async {
    try {
      final data = await _api.get(
        "/api/repondeur?appel=${Uri.encodeQueryComponent(callId)}",
      );
      return AccueilRepondeur.depuisJson(data);
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Dépose un message vocal sur un appel manqué.
  ///
  /// [mediaId] est celui d'un média DÉJÀ TÉLÉVERSÉ (`POST /api/media`) : le
  /// serveur ne reçoit pas d'octets ici, il rattache un média existant à
  /// l'appel. Il refuse tout ce qui n'est pas audio.
  ///
  /// ⚠️ LÈVE, ET C'EST VOULU — contrairement à la lecture ci-dessus. Un dépôt
  /// qui échoue doit se dire : la personne a parlé, elle doit savoir que son
  /// message n'est pas parti. Les refus attendus portent un code lisible :
  /// `CALL_ANSWERED`, `CALL_TOO_OLD`, `ALREADY_LEFT`, `GROUP_CALL`,
  /// `NO_ANSWERING_MACHINE`.
  Future<void> deposerMessagerie({
    required String callId,
    required String mediaId,
  }) async {
    await _api.post("/api/calls/${Uri.encodeComponent(callId)}/voicemail", {
      "mediaId": mediaId,
    });
  }
}

/// Un message d'accueil enregistré sur mon compte.
class Accueil {
  const Accueil({
    required this.id,
    required this.libelle,
    required this.actif,
    required this.url,
  });

  final String id;
  final String libelle;

  /// Celui qu'on fait entendre. Le serveur n'en garde qu'un actif à la fois,
  /// et le bascule EN TRANSACTION — sans quoi le compte pourrait se retrouver
  /// sans aucun accueil désigné : un répondeur muet qui se déclare prêt.
  final bool actif;

  /// URL relative du média (`/api/media/<id>`).
  final String url;

  static Accueil? depuisJson(Map<String, dynamic> j) {
    final id = j["id"]?.toString();
    if (id == null || id.isEmpty) return null;
    final media = j["media"];
    return Accueil(
      id: id,
      libelle: j["libelle"]?.toString() ?? "",
      actif: j["actif"] == 1 || j["actif"] == true,
      url: (media is Map ? media["url"]?.toString() : null) ?? "",
    );
  }
}

/// MON répondeur : l'interrupteur, l'absence, et mes accueils.
class MonRepondeur {
  const MonRepondeur({
    required this.actif,
    required this.jusquA,
    required this.accueils,
  });

  final bool actif;

  /// Fin de l'absence en cours, ou `null`.
  ///
  /// ⚠️ LE SERVEUR NE LA REND QUE SI ELLE EST ENCORE DEVANT NOUS : une date
  /// passée n'est pas une absence, et l'écran afficherait « actif jusqu'à 9 h »
  /// à midi.
  final DateTime? jusquA;

  final List<Accueil> accueils;

  bool get enAbsence => jusquA != null;

  static MonRepondeur depuisJson(Map<String, dynamic> j) => MonRepondeur(
    actif: j["actif"] == true,
    // ⚠️ `GET` NE REND PAS `jusquA`, les `POST` si. On lit donc
    // défensivement plutôt que de supposer : un champ absent vaut « pas
    // d'absence », ce qui est le cas le plus fréquent.
    jusquA: DateTime.tryParse(j["jusquA"]?.toString() ?? ""),
    accueils:
        (j["accueils"] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(Accueil.depuisJson)
            .whereType<Accueil>()
            .toList() ??
        const [],
  );
}

/// Durée maximale d'une absence — MIROIR d'`ABSENCE_MAX_MINUTES` côté serveur.
///
/// ⚠️ LA VRAIE BORNE EST CELLE DU SERVEUR, et cette constante ne fait que lui
/// éviter un aller-retour : au-delà, la route répond 400. Un écran n'est pas le
/// seul chemin vers une API.
const absenceMaxMinutes = 24 * 60;

/// Durée maximale d'un message d'accueil — MIROIR d'`ACCUEIL_MAX_MS` côté web.
///
/// 🔴 LE MOBILE N'AVAIT AUCUNE BORNE, et le serveur n'en pose pas : il ne
/// vérifie que le type du fichier, jamais sa durée. On pouvait donc enregistrer
/// dix minutes, les téléverser — la donnée est payée — et les faire subir à
/// chaque appelant, y compris sur le web où la même limite existe pourtant
/// depuis le début.
///
/// Trente secondes : au-delà, l'appelant raccroche avant le bip. Ce n'est pas
/// une limite technique mais une limite d'usage.
const accueilMaxMs = 30 * 1000;

/// MON répondeur — la partie « réglages », par opposition à l'appelant.
extension MonRepondeurApi on RepondeurRepository {
  Future<MonRepondeur> lire() async =>
      MonRepondeur.depuisJson(await _api.get("/api/repondeur"));

  /// Allume ou éteint le répondeur.
  Future<MonRepondeur> activer(bool actif) async => MonRepondeur.depuisJson(
    await _api.post("/api/repondeur", {"actif": actif}),
  );

  /// Pose une absence de [minutes], ou la lève avec `0`.
  ///
  /// ⚠️ POSER UNE ABSENCE ALLUME LE RÉPONDEUR, côté serveur : demander qu'on
  /// réponde à sa place en laissant l'interrupteur éteint n'aurait aucun sens.
  /// L'écran n'a donc pas à l'allumer lui-même.
  Future<MonRepondeur> poserAbsence(int minutes) async =>
      MonRepondeur.depuisJson(
        await _api.post("/api/repondeur", {"absenceMinutes": minutes}),
      );

  /// Ajoute un accueil depuis un média déjà téléversé, et le rend actif.
  Future<MonRepondeur> ajouterAccueil({
    required String mediaId,
    required String libelle,
  }) async => MonRepondeur.depuisJson(
    await _api.post("/api/repondeur", {"mediaId": mediaId, "libelle": libelle}),
  );

  /// Désigne l'accueil qu'on fait entendre.
  Future<MonRepondeur> choisirAccueil(String id) async =>
      MonRepondeur.depuisJson(
        await _api.post(
          "/api/repondeur?actif=${Uri.encodeQueryComponent(id)}",
          const {},
        ),
      );

  /// Supprime un accueil.
  ///
  /// ⚠️ SUPPRIMER L'ACCUEIL ACTIF ÉTEINT LE RÉPONDEUR, côté serveur : un
  /// répondeur allumé sans rien à faire entendre est un piège.
  Future<MonRepondeur> retirerAccueil(String id) async =>
      MonRepondeur.depuisJson(
        await _api.delete(
          "/api/repondeur?accueil=${Uri.encodeQueryComponent(id)}",
        ),
      );
}

/* ══════════════════ LES PLAGES PROGRAMMÉES ══════════════════ */

/// Une plage : un jour, une heure de début, une heure de fin.
///
/// 🔴 CE N'EST PAS UNE VARIANTE DE L'ABSENCE, c'est un troisième mode.
/// L'absence dit « à partir de maintenant, et pendant trois heures ». Une plage
/// dit « tous les lundis, de 10 h à 12 h » — elle revient, et n'a pas de fin
/// tant qu'on ne la retire pas. C'est ce qui la rend dangereuse : d'où sa
/// péremption automatique au bout de deux semaines, décidée par le serveur.
///
/// ⚠️ LES HEURES SONT DES MINUTES DEPUIS MINUIT, et non « 10:00 ». Une chaîne
/// se compare par ordre alphabétique — « 9:30 » y passe APRÈS « 10:00 ».
class PlageRepondeur {
  const PlageRepondeur({
    required this.id,
    required this.jour,
    required this.debutMin,
    required this.finMin,
    required this.accueilId,
    required this.expireLe,
  });

  final String id;

  /// 0 = dimanche … 6 = samedi — la convention de `Date.getDay()` côté serveur.
  ///
  /// ⚠️ CE N'EST PAS CELLE DE DART, où `DateTime.weekday` fait 1 = lundi …
  /// 7 = dimanche. Les deux se ressemblent assez pour qu'on les confonde, et
  /// assez peu pour que tout se décale d'un jour. La conversion se fait à
  /// l'écran, une seule fois.
  final int jour;

  final int debutMin;
  final int finMin;

  /// L'accueil propre à cette plage, ou `null` pour celui de tous les jours.
  final String? accueilId;

  /// Fin de validité — deux semaines après la pose.
  final DateTime? expireLe;

  /// Cette plage a-t-elle cessé de s'appliquer ?
  ///
  /// ⚠️ LE SERVEUR REND AUSSI LES PÉRIMÉES, avec leur date, et c'est voulu : les
  /// cacher ferait disparaître de l'écran une programmation qu'on cherche
  /// justement à retrouver pour la relancer. C'est à l'écran de dire
  /// « expirée », pas à la base de l'effacer.
  bool get expiree =>
      expireLe != null && !expireLe!.isAfter(DateTime.now());

  static PlageRepondeur? depuisJson(Map<String, dynamic> j) {
    final id = j["id"]?.toString();
    if (id == null || id.isEmpty) return null;
    final jour = int.tryParse(j["jour"]?.toString() ?? "");
    final debut = int.tryParse(j["debutMin"]?.toString() ?? "");
    final fin = int.tryParse(j["finMin"]?.toString() ?? "");
    if (jour == null || debut == null || fin == null) return null;
    return PlageRepondeur(
      id: id,
      jour: jour,
      debutMin: debut,
      finMin: fin,
      accueilId: j["accueilId"]?.toString(),
      expireLe: DateTime.tryParse(j["expireLe"]?.toString() ?? ""),
    );
  }
}

/// Nombre maximal de plages par compte — MIROIR de `PLAGES_MAX` côté serveur.
const plagesMax = 40;

/// Les plages programmées de mon compte.
extension PlagesRepondeurApi on RepondeurRepository {
  Future<List<PlageRepondeur>> listerPlages() async =>
      _lirePlages(await _api.get("/api/repondeur/plages"));

  /// Pose une ou plusieurs plages d'un coup.
  ///
  /// 🔴 LE FUSEAU PART D'ICI, ET C'EST LE SEUL ENDROIT QUI LE CONNAISSE. Le
  /// serveur ne peut que deviner le sien, qui n'est presque jamais celui de
  /// l'utilisateur : une plage « lundi 10 h » posée depuis Douala s'ouvrirait
  /// à 11 h locale si on laissait le serveur trancher.
  ///
  /// ⚠️ EN CAS D'ÉCHEC, ON N'ENVOIE RIEN PLUTÔT QU'UN FUSEAU FAUX : le serveur
  /// retombe alors sur UTC, ce qu'il documente, au lieu de se voir imposer une
  /// zone inventée. Mieux vaut un repli connu qu'une valeur plausible.
  Future<List<PlageRepondeur>> ajouterPlages(
    List<Map<String, Object?>> plages,
  ) async {
    final fuseau = await fuseauLocal();
    return _lirePlages(
      await _api.post("/api/repondeur/plages", {
        "plages": [
          for (final p in plages)
            if (fuseau == null) p else {...p, "fuseau": fuseau},
        ],
      }),
    );
  }

  Future<List<PlageRepondeur>> retirerPlage(String id) async => _lirePlages(
    await _api.delete(
      "/api/repondeur/plages?id=${Uri.encodeQueryComponent(id)}",
    ),
  );

  List<PlageRepondeur> _lirePlages(Map<String, dynamic> data) =>
      (data["plages"] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(PlageRepondeur.depuisJson)
          .whereType<PlageRepondeur>()
          .toList() ??
      const [];
}

/// Le nom IANA du fuseau de cet appareil (« Africa/Douala »), ou `null`.
///
/// ⚠️ NE JAMAIS REMPLACER PAR `DateTime.now().timeZoneName`, qui rend une
/// ABRÉVIATION (« WAT », « CEST »). Le serveur la passe à `Intl`, qui ne la
/// reconnaît pas, et retombe silencieusement sur UTC : les plages s'ouvriraient
/// à côté sans que rien ne le signale.
Future<String?> fuseauLocal() async {
  try {
    final nom = await FlutterTimezone.getLocalTimezone();
    return nom.isEmpty ? null : nom;
  } catch (_) {
    // Greffon absent, plateforme muette : le serveur retombera sur UTC, ce
    // qu'il documente. Lever ici empêcherait de poser la moindre plage.
    return null;
  }
}
