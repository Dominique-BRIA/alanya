import 'package:flutter/foundation.dart';

/// Nature d'un transfert. Elle décide de ce que la notification peut promettre.
enum SorteTransfert {
  /// Envoi de médias vers le serveur.
  envoi,

  /// Téléchargement d'un fichier vers le stockage du téléphone.
  telechargement,

  /// Installation d'un modèle de traduction ML Kit.
  ///
  /// 🚫 **JAMAIS DE POURCENTAGE POUR CELUI-CI.** ML Kit ne rend que « terminé »
  /// ou « échoué » — aucune API n'expose l'avancement, contrairement au
  /// navigateur qui, lui, donne une fraction. Une barre indéterminée dit la
  /// vérité ; un pourcentage inventé serait un mensonge que l'utilisateur
  /// croirait, et qui le ferait attendre en regardant un chiffre faux.
  langue,
}

/// Un transfert en cours, échoué ou terminé.
class Transfert {
  Transfert({
    required this.id,
    required this.sorte,
    required this.titre,
    this.fraction,
    this.echoue = false,
    this.termine = false,
    this.annuler,
  });

  /// Identité stable : elle sert AUSSI d'identifiant de notification, pour que
  /// deux avancements du même transfert se remplacent au lieu de s'empiler.
  final String id;
  final SorteTransfert sorte;

  /// Ce que lit l'utilisateur : « Photo », « rapport.pdf », « English ».
  final String titre;

  /// Avancement entre 0 et 1, ou `null` quand il est INCONNAISSABLE — modèle de
  /// langue, ou réponse HTTP sans `Content-Length`.
  double? fraction;

  bool echoue;
  bool termine;

  /// Interruption, quand elle est possible. Absente pour un modèle de langue :
  /// c'est Google Play Services qui télécharge, nous ne tenons pas la requête.
  final VoidCallback? annuler;

  bool get determine => fraction != null;

  /// Première ligne de la notification : ce qui se passe.
  ///
  /// Les libellés vivent ICI et non chez l'appelant : la notification est posée
  /// par la couche système, l'écran par Flutter, et deux textes séparés
  /// finiraient par se contredire.
  String get titreNotification {
    if (echoue) {
      switch (sorte) {
        case SorteTransfert.envoi:
          return "Envoi impossible";
        case SorteTransfert.telechargement:
          return "Téléchargement impossible";
        case SorteTransfert.langue:
          return "Installation impossible";
      }
    }
    switch (sorte) {
      case SorteTransfert.envoi:
        return "Envoi en cours";
      case SorteTransfert.telechargement:
        return "Téléchargement en cours";
      case SorteTransfert.langue:
        return "Installation de la langue";
    }
  }

  /// Seconde ligne : QUOI, et où ça en est.
  ///
  /// Le pourcentage n'apparaît que s'il est connu. Écrire « 0 % » sur un
  /// transfert dont on ignore la taille ferait croire à un blocage.
  String get sousTitreNotification {
    if (echoue) return titre;
    // 🔴 UNE LANGUE N'AURA JAMAIS DE POURCENTAGE — signalé par le user le
    // 19/08/2026 : « je ne vois pas de progression, juste [la barre] qui
    // défile ». ML Kit ne rend qu'un booléen a la fin, aucun rappel
    // d'avancement n'existe dans son API. La barre indeterminee est donc juste,
    // mais muette : elle ne distingue pas « ça avance » de « c'est bloqué ». Le
    // TEXTE porte ce que la barre ne peut pas dire — le poids et le fait que
    // la durée est inconnue — au lieu de laisser deviner.
    if (sorte == SorteTransfert.langue) {
      return "$titre · quelques dizaines de Mo, durée inconnue";
    }
    final f = fraction;
    if (f == null) return titre;
    return "$titre · ${(f * 100).round().clamp(0, 100)} %";
  }
}

/// Tous les transferts de l'application, en un seul endroit.
///
/// POURQUOI CE MAGASIN EXISTE. La progression d'un envoi vivait dans
/// `EnvoiMediaStore`, celle d'un téléchargement n'existait pas, et celle d'un
/// modèle de langue nulle part. Trois chemins, trois façons de ne rien montrer.
/// Or la question de l'utilisateur est une seule : « où en sont mes
/// transferts ? » — y compris **sans ouvrir l'application**, ce qui exige un
/// point unique qu'une notification puisse suivre.
///
/// ⚠️ **Singleton assumé**, comme `RingtoneService`, `PushService` et
/// `EnvoiMediaStore`. Un transfert n'appartient à aucun écran : c'est
/// exactement la leçon du 17/08/2026, où une file d'envois vivant dans l'état
/// d'un écran perdait ses médias dès qu'on quittait la conversation.
///
/// ⚠️ **Ce magasin ne détient JAMAIS de `BuildContext`** — même règle que
/// `EnvoiMediaStore`. Ce qui doit afficher s'y abonne ; lui ne connaît personne.
class CentreTransferts extends ChangeNotifier {
  CentreTransferts._();
  static final CentreTransferts instance = CentreTransferts._();

  final Map<String, Transfert> _transferts = {};

  /// Rapporteur branché par la couche de notification. Il reçoit chaque
  /// changement, y compris la disparition (`retire: true`).
  ///
  /// Un rappel plutôt qu'un `addListener` : la notification a besoin de savoir
  /// QUEL transfert a changé pour ne rafraîchir que celui-là. Un écouteur sans
  /// argument obligerait à re-publier les vingt notifications à chaque pour
  /// cent.
  void Function(Transfert transfert, {required bool retire})? surChangement;

  List<Transfert> get enCours =>
      _transferts.values.where((t) => !t.termine && !t.echoue).toList();

  bool get actif => enCours.isNotEmpty;

  Transfert? parId(String id) => _transferts[id];

  /// Déclare un transfert et l'annonce. À appeler AVANT le premier octet.
  Transfert demarrer({
    required String id,
    required SorteTransfert sorte,
    required String titre,
    double? fraction,
    VoidCallback? annuler,
  }) {
    final t = Transfert(
      id: id,
      sorte: sorte,
      titre: titre,
      // Un envoi ou un téléchargement part de zéro ; une langue part d'inconnu.
      fraction: sorte == SorteTransfert.langue ? null : (fraction ?? 0),
      annuler: annuler,
    );
    _transferts[id] = t;
    _annoncer(t);
    notifyListeners();
    return t;
  }

  /// Avancement. [fraction] nulle = indéterminé, et le reste.
  ///
  /// ⚠️ **Silencieux si rien n'a bougé d'un pour cent entier.** Le compteur
  /// d'octets rapporte déjà par pour cent, mais un envoi multi-fichiers peut
  /// repasser par ici plus souvent ; sans ce filtre, chaque notification serait
  /// republiée des centaines de fois pour un seul fichier.
  void avancer(String id, double? fraction) {
    final t = _transferts[id];
    if (t == null) return;
    if (fraction != null && t.fraction != null) {
      final avant = (t.fraction! * 100).round();
      final apres = (fraction.clamp(0, 1) * 100).round();
      if (avant == apres) return;
    }
    t.fraction = fraction?.clamp(0.0, 1.0);
    _annoncer(t);
    notifyListeners();
  }

  /// Le transfert a abouti. La notification disparaît.
  ///
  /// ⚠️ On RETIRE au lieu d'afficher « terminé » : une notification de succès
  /// qui reste demande un geste pour être écartée, et vingt photos envoyées
  /// laisseraient vingt lignes à balayer. L'utilisateur voit le résultat dans la
  /// conversation, c'est là que la preuve doit être.
  void reussir(String id) {
    final t = _transferts.remove(id);
    if (t == null) return;
    t.termine = true;
    _annoncer(t, retire: true);
    notifyListeners();
  }

  /// Le transfert a échoué. La notification RESTE, elle : un échec silencieux
  /// est le pire des cas — l'utilisateur croit son fichier parti.
  ///
  /// ⚠️ **L'ENTRÉE EST CONSERVÉE**, marquée échouée, et non retirée de la table.
  /// La retirer paraissait plus propre et laissait une notification d'échec
  /// ORPHELINE : plus rien en mémoire ne la référençait, donc ni l'abandon ni le
  /// réessai ne pouvaient la faire disparaître. `enCours` la filtre déjà, ce qui
  /// suffit à ne pas la compter comme active.
  void echouer(String id) {
    final t = _transferts[id];
    if (t == null) return;
    t.echoue = true;
    _annoncer(t);
    notifyListeners();
  }

  /// Abandon demandé par l'utilisateur, depuis l'application ou la notification.
  void annuler(String id) {
    final t = _transferts.remove(id);
    if (t == null) return;
    t.annuler?.call();
    _annoncer(t, retire: true);
    notifyListeners();
  }

  void _annoncer(Transfert t, {bool retire = false}) {
    try {
      surChangement?.call(t, retire: retire);
    } catch (_) {
      // Une notification qui échoue ne doit jamais interrompre le transfert
      // lui-même : c'est le fichier qui compte, pas son affichage.
    }
  }
}
