/// LA BARRE DE L'ÉCRAN DE RESTAURATION : une seule barre pour quatre étapes.
///
/// Fonctions PURES, éprouvées par `test/restauration_progression_test.dart`.
library;

import '../../services/e2ee/e2ee_sauvegarde.dart';

/// La part de la barre que prend chaque étape, dans l'ordre.
///
/// ⚠️ LE DÉCHIFFREMENT ET LE RANGEMENT PÈSENT LE PLUS : ce sont eux qui
/// durent quand l'historique est long. Le téléchargement est souvent une ou
/// deux pages.
const _parts = {
  EtapeRestauration.ouverture: (0.0, 0.10),
  EtapeRestauration.telechargement: (0.10, 0.35),
  EtapeRestauration.dechiffrement: (0.35, 0.70),
  EtapeRestauration.rangement: (0.70, 1.0),
};

/// Où en est la barre, de 0 à 1 — ou `null` quand on ne peut pas le dire.
///
/// ⚠️ `null` VEUT DIRE « BARRE ANIMÉE », pas « rien ». L'ouverture (Argon2id)
/// ne donne aucun signe d'avancement, et un serveur ancien ne dit pas combien
/// de blocs il a : une barre qui avancerait sans savoir mentirait.
double? fractionGlobale(ProgressionRestauration p) {
  final (debut, fin) = _parts[p.etape]!;
  final total = p.total;
  if (p.etape == EtapeRestauration.ouverture) return null;
  if (total == null) return null;
  if (total <= 0) return fin;
  final dedans = (p.fait / total).clamp(0.0, 1.0);
  return debut + (fin - debut) * dedans;
}

/// Le libellé de l'étape, tel que l'écran l'affiche.
/// ⚠️ AUCUN DE CES LIBELLÉS NE PARLE DE CHIFFREMENT (décision du user,
/// 12/10/2026). « Déchiffrement des messages » ne dit rien d'utile à qui attend
/// ses conversations, et ne fait qu'ouvrir une question qu'il ne se posait pas.
/// Ils disent où l'on en est, pas comment c'est fait.
String libelleEtape(EtapeRestauration e) => switch (e) {
  EtapeRestauration.ouverture => 'Connexion à votre compte…',
  EtapeRestauration.telechargement => 'Récupération de vos messages…',
  EtapeRestauration.dechiffrement => 'Préparation des messages…',
  EtapeRestauration.rangement => 'Enregistrement sur cet appareil…',
};

/// Le compteur sous la barre : « 1 250 / 2 100 », ou rien.
String? compteur(ProgressionRestauration p) {
  final total = p.total;
  if (p.etape == EtapeRestauration.ouverture || total == null) return null;
  final unite = p.etape == EtapeRestauration.rangement ? 'messages' : 'blocs';
  return '${_milliers(p.fait)} / ${_milliers(total)} $unite';
}

String _milliers(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
