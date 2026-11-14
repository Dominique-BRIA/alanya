import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_saver_service.dart';

/// LE TÉLÉCHARGEMENT AUTOMATIQUE DES MÉDIAS REÇUS (14/11/2026).
///
/// 🐛 « L'ÉCONOMIE DE DONNÉES NE FONCTIONNE PAS » (user, 14/11/2026). Elle
/// n'était lue que par `CachedMedia`, c'est-à-dire par les médias EN CLAIR —
/// devenus rares. Chaque photo CHIFFRÉE se téléchargeait dès qu'elle
/// paraissait à l'écran, et l'application ne savait même pas distinguer le
/// Wi-Fi des données mobiles.
///
/// 🔴 LA RÈGLE, EN UN SEUL ENDROIT — sur le modèle de l'application de
/// référence (`media_download_preferences.dart`) et du web (réglage par
/// famille, `telechargement-auto.ts`) :
///   1. la photo ou le vocal que J'AI envoyé n'est jamais retenu : je l'ai
///      déjà ;
///   2. une famille éteinte ne télécharge rien d'office ; une vidéo ou un
///      document de plus de 100 Mo non plus ;
///   3. « Wi-Fi uniquement » ou « Économie de données » : d'office seulement
///      sur un réseau sans forfait (Wi-Fi, Ethernet) ;
///   4. réseau indéterminable : on s'abstient. Une photo retenue se rattrape
///      d'un toucher ; du forfait consommé, non.
///
/// ⚠️ « D'OFFICE » SEULEMENT. Un média qu'on ouvre exprès (toucher, galerie,
/// statut) se télécharge toujours : c'est une demande.
///
/// ⚠️ RÉGLAGE DE CET APPAREIL, pas du compte : le téléphone en 4G et
/// l'ordinateur au bureau n'ont pas le même forfait.
enum FamilleMedia { photo, audio, video, document }

/// La famille d'un média d'après son type MIME.
FamilleMedia familleDuMime(String mime) {
  final m = mime.toLowerCase();
  if (m.startsWith('image/')) return FamilleMedia.photo;
  if (m.startsWith('audio/')) return FamilleMedia.audio;
  if (m.startsWith('video/')) return FamilleMedia.video;
  return FamilleMedia.document;
}

class TelechargementAuto extends ChangeNotifier {
  TelechargementAuto._({Future<List<ConnectivityResult>> Function()? reseau})
      : _reseau = reseau ?? (() => Connectivity().checkConnectivity());

  static TelechargementAuto instance = TelechargementAuto._();

  /// Pour les essais : un réseau simulé, et des réglages neufs.
  @visibleForTesting
  static void remplacerPourEssais(Future<List<ConnectivityResult>> Function() reseau) {
    instance = TelechargementAuto._(reseau: reseau);
  }

  final Future<List<ConnectivityResult>> Function() _reseau;

  static const _prefixe = 'telechargement_auto.';
  static const _cleWifi = 'telechargement_wifi_seulement';

  /// Toutes les familles allumées par défaut : c'est le comportement d'avant
  /// pour qui ne touche à rien…
  final Map<FamilleMedia, bool> _familles = {for (final f in FamilleMedia.values) f: true};

  /// …mais seulement en Wi-Fi, comme l'application de référence : télécharger
  /// d'office sur données mobiles, c'est dépenser le forfait sans qu'on l'ait
  /// demandé — inacceptable là où les données coûtent cher.
  bool _wifiSeulement = true;

  bool famille(FamilleMedia f) => _familles[f] ?? true;
  bool get wifiSeulement => _wifiSeulement;

  /// À appeler au démarrage, avant le premier rendu des médias.
  Future<void> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final f in FamilleMedia.values) {
        _familles[f] = p.getBool('$_prefixe${f.name}') ?? true;
      }
      _wifiSeulement = p.getBool(_cleWifi) ?? true;
      notifyListeners();
    } catch (_) {
      // Préférences illisibles : les défauts tiennent.
    }
  }

  Future<void> changerFamille(FamilleMedia f, bool actif) async {
    _familles[f] = actif;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool('$_prefixe${f.name}', actif);
    } catch (_) {}
  }

  Future<void> changerWifiSeulement(bool actif) async {
    _wifiSeulement = actif;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_cleWifi, actif);
    } catch (_) {}
  }

  /// Vrai si l'appareil est sur un réseau sans forfait (Wi-Fi, Ethernet).
  /// Indéterminable : faux.
  Future<bool> reseauSansForfait() async {
    try {
      final r = await _reseau();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// Au-delà, une vidéo ou un document attend toujours un toucher, même en
  /// Wi-Fi : on ne remplit pas le stockage d'un petit téléphone avec des
  /// fichiers que personne n'a encore ouverts.
  static const tailleMaxAuto = 100 * 1024 * 1024;

  /// Un média de cette [f]amille peut-il se télécharger D'OFFICE, maintenant ?
  /// [moi] : je l'ai envoyé. [taille] : son poids en octets, s'il est connu.
  ///
  /// ⚠️ « JE L'AI ENVOYÉ » NE VAUT PASSE-DROIT QUE POUR UNE PHOTO OU UN VOCAL.
  /// Envoyée d'ici, la copie est déjà dans le cache et rien ne se télécharge ;
  /// envoyée depuis le web, une vidéo de 80 Mo partirait sur le forfait.
  Future<bool> autoriser(FamilleMedia f, {bool moi = false, int? taille}) async {
    final leger = f == FamilleMedia.photo || f == FamilleMedia.audio;
    if (moi && leger) return true;
    if (!leger && taille != null && taille > tailleMaxAuto) return false;
    if (!famille(f)) return false;
    if (_wifiSeulement || DataSaverService.instance.isOn) return reseauSansForfait();
    return true;
  }
}
