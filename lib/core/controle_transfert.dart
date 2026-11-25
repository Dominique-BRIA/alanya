import 'dart:async';

import 'package:flutter/foundation.dart';

/// METTRE UN TRANSFERT EN PAUSE, ET LE REPRENDRE.
///
/// 🔴 DEMANDE DU USER, 25/11/2026 : « on doit pouvoir mettre pause à un envoi
/// ou même à un téléchargement ». L'ENVOI l'a depuis le 29/10 — il passe par
/// Android, qu'on peut simplement cesser d'alimenter. Le TÉLÉCHARGEMENT, lui,
/// est une requête HTTP tenue par l'application : il faut de quoi la couper et
/// la reprendre. C'est ce que fait cette classe.
///
/// Jumelle de `STAGE-WEB/src/services/controle-envoi.ts`.
///
/// 🔴 UNE PAUSE COUPE LES OCTETS EN VOL. Lever un drapeau et attendre la fin de
/// la requête laisserait descendre le fichier entier après le toucher : sur un
/// forfait mobile, c'est précisément la donnée qu'on voulait garder. La requête
/// est donc interrompue — et ce qui est déjà écrit sur le disque reste, car la
/// reprise par plage (`Range`) repart de la longueur du fichier partiel.
///
/// ⚠️ UNE PAUSE NE SURVIT PAS À LA SESSION (décision du user). Rien n'est écrit
/// sur le disque : cet état vit en mémoire. Application relancée, le
/// téléchargement redevient un téléchargement coupé ordinaire, que la reprise
/// rattrape déjà.
///
/// ⚠️ CE N'EST PAS UNE ANNULATION. Une pause n'use aucun essai et ne remonte
/// aucune erreur : le téléchargeur attend, il n'échoue pas. Sans cette
/// distinction, mettre en pause six fois aurait épuisé les essais et fait
/// échouer l'ouverture comme une panne réseau.
class ControleTransfert {
  final enPause = ValueNotifier<bool>(false);

  /// Les reprises à libérer : un completer par point de contrôle en attente.
  final _attentes = <Completer<void>>[];

  /// De quoi couper ce qui est en vol — une entrée par requête en cours.
  final _arrets = <void Function()>{};

  void pause() {
    if (enPause.value) return;
    enPause.value = true;
    // Copie : un arrêt se retire de l'ensemble en s'exécutant.
    for (final arret in _arrets.toList()) {
      try {
        arret();
      } catch (_) {
        // Une requête déjà finie : rien à couper.
      }
    }
  }

  void reprendre() {
    if (!enPause.value) return;
    enPause.value = false;
    final attentes = List<Completer<void>>.from(_attentes);
    _attentes.clear();
    for (final c in attentes) {
      if (!c.isCompleted) c.complete();
    }
  }

  void basculer() => enPause.value ? reprendre() : pause();

  /// Le POINT DE CONTRÔLE, à appeler avant chaque essai : rend la main tout de
  /// suite quand rien n'est en pause, attend la reprise sinon.
  Future<void> point() {
    if (!enPause.value) return Future<void>.value();
    final c = Completer<void>();
    _attentes.add(c);
    return c.future;
  }

  /// Inscrit de quoi interrompre une requête en vol ; rend la fonction qui
  /// retire cette inscription.
  ///
  /// ⚠️ LE RETRAIT EST OBLIGATOIRE à la fin de la requête, succès ou échec :
  /// sans lui, une pause tardive couperait des requêtes déjà terminées, et
  /// l'ensemble grossirait d'un essai à l'autre.
  void Function() inscrire(void Function() arret) {
    _arrets.add(arret);
    return () => _arrets.remove(arret);
  }

  void liberer() {
    reprendre();
    _arrets.clear();
    enPause.dispose();
  }
}
