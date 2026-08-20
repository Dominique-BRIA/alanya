/// Traduction SUR L'APPAREIL, par ML Kit.
///
/// Miroir Dart de `src/services/traduction-locale.ts` du client web : le
/// navigateur y expose `Translator`/`LanguageDetector`, Android expose ML Kit.
/// Les deux répondent à la même promesse — les modèles sont téléchargés puis
/// gardés localement, le texte ne sort jamais de l'appareil, et rien n'est
/// facturé. Les décisions qui ne se devinent pas ont été reprises telles
/// quelles du web plutôt que redécouvertes ; celles qui DIFFÈRENT sont
/// signalées ci-dessous.
///
/// Ce fichier ne connaît ni l'écran, ni les préférences, ni la langue de
/// l'interface : il ne répond qu'à « cet appareil sait-il traduire ce couple,
/// et comment ».
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'centre_transferts.dart';
import 'texte_recherche.dart';

/// Le moteur n'existe que sur mobile : ML Kit n'a pas d'implémentation web ni
/// bureau. Ailleurs, il n'y a PAS de repli vers un service en ligne — envoyer
/// le contenu d'un message à un tiers est précisément ce que ce lot supprime.
bool get moteurAppareilPresent {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

/// Codes de langue.
///
/// Même normalisation que le web, et pour la même raison : le détecteur rend
/// `nb` (bokmål) là où le catalogue du projet — et ML Kit lui-même — dit `no`,
/// et décline le chinois en `zh-Hans`/`zh-CN` là où les deux ne connaissent que
/// `zh`. Sans elle, une détection correcte serait lue comme une langue inconnue
/// et le bouton « Traduire » ne servirait jamais à rien.
///
/// `und` est le code que ML Kit renvoie quand il ne se prononce pas : il vaut
/// une absence de réponse, pas une langue.
String normaliserLangue(String? code) {
  if (code == null || code.isEmpty) return "";
  final court = code.toLowerCase().replaceAll("_", "-");
  if (court == "und") return "";
  if (court == "nb" || court.startsWith("nb-") || court.startsWith("nn")) {
    return "no";
  }
  if (court.startsWith("zh")) return "zh";
  return court.length > 2 ? court.substring(0, 2) : court;
}

/// La langue, si ML Kit sait la traduire hors ligne — 59 langues, pas plus.
TranslateLanguage? langueSupportee(String? code) {
  final normalise = normaliserLangue(code);
  if (normalise.isEmpty) return null;
  return BCP47Code.fromRawValue(normalise);
}

/// État d'un couple de langues.
enum EtatCouple {
  /// Moteur absent, langue non prise en charge, ou source identique à la cible.
  indisponible,

  /// Traduisible, mais au moins un des deux modèles reste à installer.
  aTelecharger,

  /// Les deux modèles sont sur l'appareil : la traduction est immédiate.
  pret,
}

final OnDeviceTranslatorModelManager _gestionnaire =
    OnDeviceTranslatorModelManager();

/// Modèles constatés présents PENDANT CETTE SESSION.
///
/// Jamais persisté, exactement comme côté web : Android supprime les modèles
/// ML Kit quand l'espace disque devient rare, une réponse d'hier ne dit donc
/// rien d'aujourd'hui. Seule la réponse « présent » est mise en cache — un
/// « absent » doit pouvoir devenir vrai dès la fin d'un téléchargement.
final Map<String, bool> _modelesPresents = {};

/// Oublie les sondages, pour réévaluer après un téléchargement.
void reevaluerModeles() => _modelesPresents.clear();

Future<bool> _modelePresent(TranslateLanguage langue) async {
  final cle = langue.bcpCode;
  final connu = _modelesPresents[cle];
  if (connu == true) return true;
  try {
    final present = await _gestionnaire.isModelDownloaded(cle);
    _modelesPresents[cle] = present;
    return present;
  } catch (_) {
    // Services Google Play absents ou trop anciens, politique d'entreprise :
    // dans tous les cas, on ne sait pas traduire.
    return false;
  }
}

/// Ce que l'appareil sait faire de ce couple, ici et maintenant.
///
/// ⚠️ **Différence avec le navigateur** : Chrome raisonne par COUPLE, ML Kit
/// par LANGUE. Un couple est prêt quand ses DEUX modèles sont là — et il en
/// coûte donc deux téléchargements, jamais un seul. Le pivot par l'anglais est
/// interne à ML Kit : ne jamais l'écrire à la main, ce serait deux traductions
/// au lieu d'une et une qualité moindre.
Future<EtatCouple> etatCouple(String source, String cible) async {
  if (!moteurAppareilPresent) return EtatCouple.indisponible;
  final s = langueSupportee(source);
  final c = langueSupportee(cible);
  if (s == null || c == null || s == c) return EtatCouple.indisponible;
  final presents = await Future.wait([_modelePresent(s), _modelePresent(c)]);
  return presents.every((p) => p) ? EtatCouple.pret : EtatCouple.aTelecharger;
}

/// Les langues du couple qui restent à installer — souvent UNE SEULE.
///
/// 🐛 **LE DIALOGUE NOMMAIT LES DEUX** (signalé le 19/08/2026) : « j'ai déjà
/// téléchargé ma langue et on me propose quand même un téléchargement ». C'était
/// exact et trompeur à la fois — il manquait bien un modèle, celui de la langue
/// du MESSAGE, mais le texte réclamait aussi celui qu'on venait d'installer. On
/// ne cite désormais que ce qui manque réellement.
///
/// Rend des NOMS et non des `TranslateLanguage` : l'appelant est un écran, et
/// lui faire importer le paquet ML Kit ferait fuir la dépendance jusque dans le
/// fil de discussion pour l'unique besoin d'afficher un mot.
Future<List<String>> nomsLanguesManquantes(String source, String cible) async {
  final s = langueSupportee(source);
  final c = langueSupportee(cible);
  if (s == null || c == null || s == c) return const [];
  final manquantes = <String>[];
  for (final langue in {s, c}) {
    if (!await _modelePresent(langue)) {
      manquantes.add(nomAutonyme(langue.bcpCode));
    }
  }
  return manquantes;
}

/// Installe les modèles manquants d'un couple.
///
/// **DOIT partir d'un geste de l'utilisateur** : chaque modèle pèse quelques
/// dizaines de mégaoctets. Le déclencher depuis un `initState` ferait payer un
/// téléchargement à quelqu'un qui n'a rien demandé — c'est la même règle que
/// côté web, où Chrome la fait respecter lui-même en refusant hors clic.
///
/// ⚠️ ML Kit **n'expose aucune progression** : la seule information disponible
/// est « terminé » ou « échoué ». L'écran ne peut donc afficher qu'une attente
/// indéterminée, là où le web a une fraction.
///
/// `wifiSeulement` est vrai par défaut : télécharger 60 Mo sur des données
/// mobiles, sans le dire, serait une dépense imposée.
Future<bool> telechargerCouple(
  String source,
  String cible, {
  bool wifiSeulement = true,
}) async {
  final s = langueSupportee(source);
  final c = langueSupportee(cible);
  if (s == null || c == null || s == c) return false;
  try {
    for (final langue in {s, c}) {
      if (await _modelePresent(langue)) continue;
      if (!await telechargerLangue(langue, wifiSeulement: wifiSeulement)) {
        return false;
      }
    }
    return true;
  } catch (_) {
    // Un échec ne doit pas laisser un « présent » optimiste derrière lui.
    _modelesPresents.remove(s.bcpCode);
    _modelesPresents.remove(c.bcpCode);
    return false;
  }
}

/* ------------------------------------------------- Gestion des langues */

/// Nom d'une langue **dans sa propre langue** (autonyme).
///
/// Choix assumé : l'interface existe en 9 langues, ML Kit en traduit 59.
/// Traduire 59 noms × 9 langues, ce sont 531 libellés à écrire et à tenir à
/// jour — pour un écran que l'on ouvre trois fois dans sa vie. L'autonyme, lui,
/// ne dépend d'aucune langue d'interface : « Deutsch » se lit Deutsch en
/// français comme en chinois, et c'est précisément le mot que cherche celui qui
/// installe SA langue. La recherche accepte en plus le code et le nom anglais,
/// pour que « arabe » se trouve en tapant « ar » ou « arabic ».
const Map<String, String> _autonymes = {
  'af': 'Afrikaans',
  'sq': 'Shqip',
  'ar': 'العربية',
  'be': 'Беларуская',
  'bn': 'বাংলা',
  'bg': 'Български',
  'ca': 'Català',
  'zh': '中文',
  'hr': 'Hrvatski',
  'cs': 'Čeština',
  'da': 'Dansk',
  'nl': 'Nederlands',
  'en': 'English',
  'eo': 'Esperanto',
  'et': 'Eesti',
  'fi': 'Suomi',
  'fr': 'Français',
  'gl': 'Galego',
  'ka': 'ქართული',
  'de': 'Deutsch',
  'el': 'Ελληνικά',
  'gu': 'ગુજરાતી',
  'ht': 'Kreyòl ayisyen',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hu': 'Magyar',
  'is': 'Íslenska',
  'id': 'Bahasa Indonesia',
  'ga': 'Gaeilge',
  'it': 'Italiano',
  'ja': '日本語',
  'kn': 'ಕನ್ನಡ',
  'ko': '한국어',
  'lv': 'Latviešu',
  'lt': 'Lietuvių',
  'mk': 'Македонски',
  'ms': 'Bahasa Melayu',
  'mt': 'Malti',
  'mr': 'मराठी',
  'no': 'Norsk',
  'fa': 'فارسی',
  'pl': 'Polski',
  'pt': 'Português',
  'ro': 'Română',
  'ru': 'Русский',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'es': 'Español',
  'sw': 'Kiswahili',
  'sv': 'Svenska',
  'tl': 'Tagalog',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'th': 'ไทย',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'ur': 'اردو',
  'vi': 'Tiếng Việt',
  'cy': 'Cymraeg',
};

/// Nom lisible d'une langue, ou son code si on ne le connaît pas.
String nomAutonyme(String bcpCode) =>
    _autonymes[bcpCode] ?? bcpCode.toUpperCase();

/// Les 59 langues traduisibles hors ligne, rangées par autonyme.
///
/// Le tri passe par `comparePourTri` et non par `compareTo` : Dart compare les
/// points de code, ce qui placerait « Íslenska » et « Čeština » après
/// « Türkçe ». Même helper que le carnet d'adresses, pour la même raison.
List<TranslateLanguage> languesTraduisibles() {
  final liste = TranslateLanguage.values.toList();
  liste.sort(
    (a, b) => comparePourTri(nomAutonyme(a.bcpCode), nomAutonyme(b.bcpCode)),
  );
  return liste;
}

/// La langue correspond-elle à ce que l'utilisateur a tapé ?
///
/// On accepte l'autonyme, le code BCP-47 et le nom anglais de l'énumération :
/// « arabe » ne se trouverait pas dans « العربية », mais « ar » et « arabic »
/// y mènent tous les deux.
bool langueCorrespond(TranslateLanguage langue, String recherche) {
  if (recherche.trim().isEmpty) return true;
  return contientRecherche(nomAutonyme(langue.bcpCode), recherche) ||
      contientRecherche(langue.bcpCode, recherche) ||
      contientRecherche(langue.name, recherche);
}

/// Les langues réellement installées sur l'appareil, sondées maintenant.
///
/// ⚠️ Le greffon n'expose **aucune liste** : `ModelManager` ne sait répondre
/// que « ce modèle-ci est-il là ? ». Il faut donc poser les 59 questions. Elles
/// partent par paquets de dix plutôt que toutes d'un coup — le pont natif est
/// unique, et l'inonder ne rendrait pas la réponse plus rapide.
Future<Set<String>> languesInstallees() async {
  if (!moteurAppareilPresent) return {};
  const toutes = TranslateLanguage.values;
  final installees = <String>{};
  for (var debut = 0; debut < toutes.length; debut += 10) {
    final lot = toutes.skip(debut).take(10).toList();
    final presents = await Future.wait(lot.map(_modelePresent));
    for (var i = 0; i < lot.length; i++) {
      if (presents[i]) installees.add(lot[i].bcpCode);
    }
  }
  return installees;
}

/// Installe UNE langue. Voir [telechargerCouple] pour la règle du geste
/// utilisateur et celle du Wi-Fi.
Future<bool> telechargerLangue(
  TranslateLanguage langue, {
  bool wifiSeulement = true,
}) async {
  if (!moteurAppareilPresent) return false;
  // L'installation s'annonce dans les notifications, au même titre qu'un envoi
  // ou un téléchargement : c'est une attente de plusieurs dizaines de Mo, et
  // rien ne la signalait hors de l'écran.
  //
  // 🚫 **SANS POURCENTAGE, ET C'EST DÉFINITIF** : `downloadModel` ne rend qu'un
  // booléen, à la fin. Aucune API ML Kit n'expose l'avancement — le navigateur,
  // lui, le donne. Une barre indéterminée est la seule chose honnête ici.
  final idTransfert = "langue-${langue.bcpCode}";
  CentreTransferts.instance.demarrer(
    id: idTransfert,
    sorte: SorteTransfert.langue,
    titre: nomAutonyme(langue.bcpCode),
  );
  try {
    final ok = await _gestionnaire.downloadModel(
      langue.bcpCode,
      isWifiRequired: wifiSeulement,
    );
    if (ok) {
      _modelesPresents[langue.bcpCode] = true;
      CentreTransferts.instance.reussir(idTransfert);
    } else {
      CentreTransferts.instance.echouer(idTransfert);
    }
    return ok;
  } catch (_) {
    _modelesPresents.remove(langue.bcpCode);
    CentreTransferts.instance.echouer(idTransfert);
    return false;
  }
}

/// Désinstalle une langue et libère l'espace disque qu'elle occupait.
///
/// ⚠️ Les traducteurs du pool qui s'appuyaient dessus deviennent caducs : on
/// les ferme tous, sinon le suivant échouerait sur un modèle disparu.
Future<bool> supprimerLangue(TranslateLanguage langue) async {
  if (!moteurAppareilPresent) return false;
  try {
    final ok = await _gestionnaire.deleteModel(langue.bcpCode);
    if (ok) {
      _modelesPresents[langue.bcpCode] = false;
      await libererTraducteurs();
    }
    return ok;
  } catch (_) {
    return false;
  }
}

/* ------------------------------------------------------------------ Instances */

/// Un traducteur par couple, gardé en mémoire.
///
/// En créer un par message serait le défaut le plus coûteux possible : chaque
/// instance recharge le modèle côté natif. Le pool est libéré à la sortie de
/// la conversation.
final Map<String, OnDeviceTranslator> _pool = {};

String _cleCouple(TranslateLanguage s, TranslateLanguage c) =>
    "${s.bcpCode}>${c.bcpCode}";

OnDeviceTranslator _traducteur(TranslateLanguage s, TranslateLanguage c) {
  return _pool.putIfAbsent(
    _cleCouple(s, c),
    () => OnDeviceTranslator(sourceLanguage: s, targetLanguage: c),
  );
}

/// Ferme les traducteurs et le détecteur. Les modèles téléchargés, eux, restent.
Future<void> libererTraducteurs() async {
  final instances = _pool.values.toList();
  _pool.clear();
  for (final t in instances) {
    try {
      await t.close();
    } catch (_) {
      // Une fermeture ratée ne doit pas empêcher les suivantes.
    }
  }
  final detecteurs = _detecteurs.values.toList();
  _detecteurs.clear();
  for (final d in detecteurs) {
    try {
      await d.close();
    } catch (_) {
      // idem
    }
  }
}

/* ---------------------------------------------------------------------- File */

/// File séquentielle globale : deux écrans qui traduisent en même temps ne
/// doivent pas se disputer le pont natif.
Future<void> _file = Future<void>.value();

Future<T> _enfiler<T>(Future<T> Function() travail) {
  final suivant = _file.then((_) => travail());
  // La file ne doit pas s'arrêter sur l'échec de l'un de ses maillons.
  _file = suivant.then((_) {}, onError: (_) {});
  return suivant;
}

/* ----------------------------------------------------------------- Traduction */

/// Levée quand le couple n'est pas traduisible sur l'appareil. L'appelant
/// décide quoi en faire — proposer le téléchargement, ou renoncer.
class TraductionIndisponible implements Exception {
  const TraductionIndisponible(this.etat);
  final EtatCouple etat;

  @override
  String toString() => "TraductionIndisponible($etat)";
}

/// Traduit une liste de textes sur l'appareil, dans l'ordre reçu.
///
/// L'état du couple est vérifié AVANT : `aTelecharger` n'est pas une erreur,
/// mais l'installation ne peut partir que d'un geste de l'utilisateur —
/// traduire ici la déclencherait en douce.
Future<List<String>> traduireSurAppareil(
  String source,
  String cible,
  List<String> textes,
) async {
  final etat = await etatCouple(source, cible);
  if (etat != EtatCouple.pret) throw TraductionIndisponible(etat);
  final s = langueSupportee(source)!;
  final c = langueSupportee(cible)!;
  return _enfiler(() async {
    final traducteur = _traducteur(s, c);
    final resultats = <String>[];
    for (final texte in textes) {
      try {
        resultats.add(await traducteur.translateText(texte));
      } catch (_) {
        // Le modèle a pu être évincé entre le sondage et l'appel : on cesse
        // de le croire présent, et l'appelant pourra reproposer l'installation.
        _modelesPresents.remove(s.bcpCode);
        _modelesPresents.remove(c.bcpCode);
        _pool.remove(_cleCouple(s, c));
        throw const TraductionIndisponible(EtatCouple.aTelecharger);
      }
    }
    return resultats;
  });
}

/// Traduit un texte. Raccourci de [traduireSurAppareil] pour l'usage courant.
Future<String> traduireUnTexte(
  String source,
  String cible,
  String texte,
) async {
  final resultats = await traduireSurAppareil(source, cible, [texte]);
  return resultats.first;
}

/* ------------------------------------------------------------------ Détection */

/// Un détecteur par seuil : le seuil est figé à la construction de
/// `LanguageIdentifier`, il ne se règle pas appel par appel.
final Map<double, LanguageIdentifier> _detecteurs = {};

/// Langue d'un texte, détectée sur l'appareil, ou null.
///
/// `souple` abaisse les deux garde-fous. Repris du web, où il n'était réservé
/// qu'au moteur local : s'y tromper ne coûte qu'une traduction médiocre, que
/// l'on peut refermer d'un geste. Ici tout est local, donc le mode souple est
/// le bon défaut dès qu'il s'agit de décider s'il faut PROPOSER de traduire.
Future<String?> detecterLangue(String texte, {bool souple = false}) async {
  if (!moteurAppareilPresent) return null;
  final propre = texte.trim();
  // Sur deux ou trois caractères, la détection tire au sort.
  final longueurMinimale = souple ? 3 : 8;
  if (propre.length < longueurMinimale) return null;
  final seuil = souple ? 0.25 : 0.5;
  try {
    final detecteur = _detecteurs.putIfAbsent(
      seuil,
      () => LanguageIdentifier(confidenceThreshold: seuil),
    );
    final brut = await _enfiler(() => detecteur.identifyLanguage(propre));
    final langue = normaliserLangue(brut);
    return langue.isEmpty ? null : langue;
  } catch (_) {
    return null;
  }
}
