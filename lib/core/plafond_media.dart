/// LE PLAFOND DE TAILLE D'UN MÉDIA, tenu en un seul endroit.
///
/// 🔴 SANS CE CONTRÔLE CÔTÉ CLIENT, UN FICHIER TROP LOURD EST INTÉGRALEMENT
/// TÉLÉVERSÉ AVANT D'ÊTRE REFUSÉ. Sur un forfait mobile, une vidéo de 200 Mo
/// part en entier, prend plusieurs minutes, et se termine par un 413 que rien
/// n'annonçait. L'utilisateur a payé la donnée pour un échec.
///
/// ⚠️ ALIGNÉ SUR LE SERVEUR (`MEDIA_MAX_SIZE_MB`, 300 par défaut depuis le 17/10/2026), et non choisi
/// ici. Un plafond client plus HAUT ne servirait à rien — le serveur refuserait
/// quand même. Un plafond plus BAS interdirait des envois parfaitement légitimes
/// sans que personne ne comprenne pourquoi. Si la valeur du serveur change, ce
/// fichier est le seul à modifier de ce côté-ci.

///
/// 🔴 CE MODULE EST NÉ D'UN OUBLI PARTIEL. Le contrôle existait sur UN SEUL des
/// quatre chemins de sélection — celui des documents. La galerie interne, le
/// sélecteur système de secours et la caméra des statuts laissaient tout passer.
/// Recopier la condition à trois endroits de plus aurait reproduit la cause :
/// c'est en la dispersant qu'on avait fini par n'en avoir qu'une.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// La valeur de SECOURS, si le serveur ne dit rien.
///
/// 🔴 LA LIMITE VIENT DU SERVEUR DEPUIS LE 25/11/2026 (décision du user). Elle
/// était écrite en dur à QUATRE endroits — serveur, relais, web, téléphone — et
/// avait déjà divergé : 500 Mo côté web, 300 ici. `GET /api/maintenance`
/// l'annonce maintenant, et [noterPlafondServeur] la pose.
///
/// ⚠️ ON GARDE CELLE-CI TANT QUE LE SERVEUR N'A RIEN DIT : hors ligne, ou face
/// à un serveur plus ancien qui n'annonce rien, l'application doit continuer de
/// refuser tôt plutôt que de téléverser pour rien.
const int plafondMediaSecoursOctets = 300 * 1024 * 1024;

int _plafondOctets = plafondMediaSecoursOctets;

/// Taille maximale acceptée par le serveur, en octets.
int get plafondMediaOctets => _plafondOctets;

/// La même, en mégaoctets, pour les messages destinés à l'utilisateur.
int get plafondMediaMo => _plafondOctets ~/ (1024 * 1024);

/// Le serveur vient d'annoncer sa limite (`mediaMaxMo`).
///
/// ⚠️ LES GARDE-FOUS NE SONT PAS DE LA DÉFIANCE : un champ absent, un texte, un
/// zéro — et l'application refuserait TOUS les envois sans que personne
/// comprenne pourquoi. Une valeur qu'on ne sait pas lire est ignorée.
void noterPlafondServeur(dynamic mo) {
  final n = mo is num ? mo.toInt() : int.tryParse('$mo');
  if (n == null || n < 1 || n > 5000) return;
  _plafondOctets = n * 1024 * 1024;
}

/// Ce fichier est-il trop lourd pour être envoyé ?
bool depassePlafondMedia(int octets) => octets > plafondMediaOctets;

/// Le message annonçant ce qui a été ÉCARTÉ d'une sélection.
///
/// ⚠️ ÉCARTER PLUTÔT QUE TOUT REFUSER. Choisir dix photos dont une trop lourde
/// doit envoyer les neuf autres : rejeter la sélection entière obligerait à tout
/// recommencer en devinant laquelle pose problème. D'où le nom du fichier fautif
/// quand il n'y en a qu'un — c'est la seule information qui permet d'agir.
///
/// Rend `null` si rien n'a été écarté : à l'appelant de ne rien afficher.
String? messageMediasEcartes(List<String> noms,
    {required BuildContext context}) {
  if (noms.isEmpty) return null;
  if (noms.length == 1) {
    return tr(context, 'media_skipped_one',
        {'nom': noms.first, 'plafond': '$plafondMediaMo'});
  }
  return tr(context, 'media_skipped_many',
      {'n': '${noms.length}', 'plafond': '$plafondMediaMo'});
}
