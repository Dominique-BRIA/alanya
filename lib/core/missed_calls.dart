import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/calls/calls_repository.dart';

/// Compte des appels manqués non consultés, pour la pastille de l'onglet Appels.
///
/// POURQUOI UNE DATE PLUTÔT QU'UN ÉTAT « VU » EN BASE. Marquer chaque appel
/// comme vu demanderait une colonne de plus et une écriture à chaque ouverture
/// de l'onglet. Retenir la date de dernière consultation donne le même résultat
/// visible, sans migration : le serveur compte les appels manqués postérieurs.
///
/// ⚠️ Contrepartie assumée : la pastille est PROPRE À L'APPAREIL. Consulter ses
/// appels sur un téléphone ne l'efface pas sur un autre. Pour un compteur
/// d'affichage, c'est un compromis acceptable ; pour les messages non lus, qui
/// eux sont comptés côté serveur, ça ne le serait pas.
class MissedCalls extends ChangeNotifier {
  MissedCalls._();
  static final instance = MissedCalls._();

  static const _cle = 'appels_vus_le';

  int _count = 0;
  int get count => _count;

  /// Passe par le dépôt et non par `AuthedApi` : ce dernier n'est pas exposé
  /// comme Provider, seuls les dépôts le sont. Un `context.read<AuthedApi>()`
  /// aurait compilé sans problème puis levé une exception à l'exécution.
  CallsRepository? _repo;
  void bind(CallsRepository repo) => _repo = repo;

  /// Recharge le compte depuis le serveur.
  ///
  /// Silencieuse en cas d'échec : une pastille est un confort, elle ne doit ni
  /// afficher d'erreur ni empêcher quoi que ce soit.
  Future<void> rafraichir() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = await repo.missedCount(since: prefs.getString(_cle));
      if (n == _count) return;
      _count = n;
      notifyListeners();
    } catch (_) {}
  }

  /// L'utilisateur vient d'ouvrir l'onglet Appels : tout ce qui précède est
  /// considéré comme vu.
  Future<void> marquerVus() async {
    if (_count != 0) {
      _count = 0;
      notifyListeners();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cle, DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
  }
}
