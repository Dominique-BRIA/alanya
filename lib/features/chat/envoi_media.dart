import '../../widgets/media/media_picker_sheet.dart';

/// État d'un envoi de médias en cours, ou échoué.
///
/// POURQUOI CET OBJET EXISTE : jusqu'ici, envoyer des médias n'affichait qu'un
/// spinner de 20 px sur le trombone, et RIEN dans le fil de discussion — sur
/// huit photos en 3G, l'écran ne montrait rien pendant une minute, puis les
/// bulles apparaissaient d'un coup. Un message optimiste est bien créé, mais il
/// n'a ni URL de média (le fichier n'existe pas encore côté serveur) ni
/// progression : les deux vivent ici, à côté du message, indexées par son
/// identifiant provisoire.
///
/// Il porte aussi de quoi RÉESSAYER. C'est ce qui répare le pire défaut de
/// l'ancien code : sur huit fichiers, si le septième échouait, les six premiers
/// restaient téléversés en base SANS message qui les référence — des orphelins,
/// invisibles et jamais nettoyés — et l'utilisateur perdait tout. Les
/// identifiants déjà obtenus sont donc conservés dans [mediaIdsObtenus] : un
/// réessai reprend là où l'envoi s'est arrêté au lieu de tout recommencer.
class EnvoiMedia {
  EnvoiMedia({
    required this.tempId,
    required this.fichiers,
    required this.msgType,
    this.legende,
    this.replyToId,
  });

  /// Identifiant provisoire, partagé avec le message optimiste du fil.
  final String tempId;

  /// Fichiers d'origine, gardés EN MÉMOIRE pour le réessai.
  ///
  /// ⚠️ Coût assumé : dix photos de 3 Mo = 30 Mo retenus. Ils sont libérés dès
  /// que l'envoi aboutit (l'objet est retiré de la table). Un envoi ÉCHOUÉ les
  /// garde tant que l'utilisateur n'a pas réessayé ou abandonné — c'est le prix
  /// d'un bouton « Réessayer » qui fonctionne vraiment.
  final List<MediaPickResult> fichiers;

  final String msgType;
  final String? legende;
  final String? replyToId;

  /// Médias déjà téléversés, dans l'ordre des [fichiers].
  final List<String> mediaIdsObtenus = [];

  /// Index du fichier en cours (0 pour le premier).
  int indexCourant = 0;

  /// Progression du fichier en cours, de 0 à 1.
  double progressionFichier = 0;

  /// Vrai quand l'envoi a échoué et attend une décision de l'utilisateur.
  bool echoue = false;

  /// Message d'erreur à afficher dans la bulle.
  String? erreur;

  int get total => fichiers.length;

  /// Progression GLOBALE, de 0 à 1 : les fichiers terminés comptent pour 1, le
  /// fichier courant pour sa fraction.
  ///
  /// Calculée sur le NOMBRE de fichiers et non sur les octets : c'est une
  /// approximation (une vidéo de 40 Mo ne vaut pas une photo de 200 Ko), mais
  /// elle avance de façon régulière et lisible. Le poids réel ferait stagner la
  /// barre à 3 % pendant la vidéo, puis sauter à 100 % — moins informatif.
  double get progression {
    if (total == 0) return 0;
    final termines = mediaIdsObtenus.length;
    if (termines >= total) return 1;
    return (termines + progressionFichier.clamp(0, 1)) / total;
  }

  /// Vignette locale à afficher pendant l'envoi : le premier fichier image.
  ///
  /// Une image locale s'affiche INSTANTANÉMENT, avant tout réseau — c'est ce qui
  /// fait qu'un envoi ressemble à WhatsApp plutôt qu'à un formulaire.
  MediaPickResult? get apercu {
    for (final f in fichiers) {
      if (f.mimeType.startsWith('image/')) return f;
    }
    return fichiers.isNotEmpty ? fichiers.first : null;
  }
}
