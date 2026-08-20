import 'package:flutter/foundation.dart';

import '../features/contacts/contact_lists_repository.dart';
import '../models/contact_list.dart';
import 'api_client.dart';
import 'texte_recherche.dart';
import 'token_storage.dart';

/// Ne garde que les chiffres — un numéro se compare sans ses espaces.
String _chiffres(String brut) => brut.replaceAll(RegExp(r'\D'), '');

/// Quelle sonnerie jouer pour un appelant, d'après ses listes de contacts.
///
/// 🔴 CE MAILLON MANQUAIT. La liste stockait bien son `ringtone`, l'écran
/// laissait bien le choisir, et le serveur le rendait — mais **personne ne le
/// lisait à l'arrivée d'un appel** : `startIncoming()` jouait l'asset embarqué,
/// sans condition. La fonctionnalité était complète de bout en bout sauf sur le
/// seul geste qui la rend visible.
///
/// ⚠️ **UN APPEL NE DOIT JAMAIS ATTENDRE LE RÉSEAU POUR SONNER.** Les listes
/// sont donc tenues EN MÉMOIRE et alimentées par les écrans qui les chargent
/// déjà ; si elles ne sont pas encore là, on rend `null` et l'appel sonne avec
/// la sonnerie par défaut. Mieux vaut la mauvaise sonnerie que le silence.
///
/// 🔴 **C'EST AUSSI LA SOURCE UNIQUE DE LA RANGÉE DE FILTRES** (19/08/2026).
/// L'écran des conversations en gardait sa PROPRE copie, chargée une seule fois
/// dans son `initState` : créer ou renommer une liste depuis le carnet ne se
/// voyait qu'au redémarrage de l'application. Deux copies de la même donnée, et
/// une seule des deux se rafraîchissait. En faire un `ChangeNotifier` supprime
/// la classe de problème : qui modifie une liste appelle [alimenter], et tout ce
/// qui l'affiche se remet à jour.
class SonneriesDeListes extends ChangeNotifier {
  SonneriesDeListes(this._depot, this._api, this._jetons);

  final ContactListsRepository _depot;
  final ApiClient _api;
  final TokenStorage _jetons;

  List<ListeContacts> _cache = const [];
  bool _chargementLance = false;

  /// Les listes connues. Jamais nulle : vide tant que rien n'est chargé.
  List<ListeContacts> get listes => _cache;

  /// Alimente le cache depuis un écran qui vient de charger les listes.
  ///
  /// Passer par là plutôt que de refaire l'appel évite une seconde requête pour
  /// la même donnée, et garde le cache frais à chaque création ou modification
  /// de liste — les écrans concernés appellent cette méthode.
  void alimenter(List<ListeContacts> listes) {
    _cache = listes;
    _chargementLance = true;
    notifyListeners();
  }

  /// Recharge depuis le serveur. Rend `false` en cas d'échec, sans lever.
  Future<bool> rafraichir() async {
    try {
      alimenter(await _depot.list());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Charge les listes une fois, en tâche de fond, sans jamais lever.
  ///
  /// Sert le cas où un appel arrive avant que le moindre écran n'ait chargé les
  /// listes : ce premier appel sonnera par défaut, les suivants seront justes.
  Future<void> prechargerSiBesoin() async {
    if (_chargementLance) return;
    _chargementLance = true;
    try {
      alimenter(await _depot.list());
    } catch (_) {
      // Silencieux : une sonnerie personnalisée est un confort, jamais un dû.
      _chargementLance = false;
    }
  }

  /// La liste qui décide de la sonnerie pour cet appelant, ou `null`.
  ///
  /// ⚠️ **Une personne peut appartenir à PLUSIEURS listes.** Il faut donc une
  /// règle, et elle doit être stable : sans elle, la sonnerie changerait d'un
  /// appel à l'autre au gré de l'ordre rendu par le serveur. On retient la
  /// **première par ordre alphabétique** parmi celles qui portent une sonnerie —
  /// arbitraire, mais prévisible, et l'utilisateur peut la deviner.
  ListeContacts? listePourAppelant({String? callerId, String? numero}) {
    final id = callerId?.toLowerCase();
    final num = numero == null ? "" : _chiffres(numero);
    final candidates =
        _cache
            .where((l) => l.ringtone != null && l.ringtone!.isNotEmpty)
            .where(
              (l) => l.members.any((m) {
                if (id != null && m.id.toLowerCase() == id) return true;
                return num.isNotEmpty && _chiffres(m.publicNumber) == num;
              }),
            )
            .toList()
          ..sort((a, b) => comparePourTri(a.name, b.name));
    return candidates.isEmpty ? null : candidates.first;
  }

  /// L'URL JOUABLE de la sonnerie de cet appelant, ou `null` pour la défaut.
  ///
  /// ⚠️ Le catalogue rend une URL RELATIVE (`/api/media/<id>`) et la route des
  /// médias exige un jeton, que le lecteur audio ne sait pas joindre en en-tête.
  /// Il passe donc en paramètre, comme partout ailleurs dans l'application.
  /// Sans cela, la lecture rendrait un silence sans erreur — le pire des échecs.
  Future<String?> urlPourAppelant({String? callerId, String? numero}) async {
    final liste = listePourAppelant(callerId: callerId, numero: numero);
    final relative = liste?.ringtone;
    if (relative == null || relative.isEmpty) return null;
    if (relative.startsWith("http://") || relative.startsWith("https://")) {
      return relative;
    }
    final jeton = await _jetons.accessToken;
    if (jeton == null || jeton.isEmpty) return null;
    return "${_api.baseUrl}$relative?token=$jeton";
  }
}
