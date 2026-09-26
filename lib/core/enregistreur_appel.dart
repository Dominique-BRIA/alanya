import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Le résultat d'un enregistrement : les CHEMINS des deux fichiers AAC (voix de
/// l'agent, voix du correspondant) et la durée.
///
/// 🔴 **DES CHEMINS, PLUS DES OCTETS.** L'ancienne version lisait les deux
/// pistes en mémoire et effaçait aussitôt les fichiers ; un échec d'upload
/// perdait alors l'enregistrement, et un appel long menaçait l'OOM. Désormais
/// les fichiers RESTENT sur disque jusqu'à confirmation du serveur, et l'upload
/// les lit en flux — voir `EnregistrementsEnAttente`.
typedef FichiersAppel = ({String agent, String client, int dureeMs});

/// Enregistre une conversation d'agent, sur autorisation du serveur.
///
/// 🔴 **CÔTÉ NATIF, PAS LE `MediaRecorder` DU GREFFON.** La première version
/// lançait deux `MediaRecorder` de `flutter_webrtc`. Vérifié dans le code
/// Android du greffon APRÈS coup (20/08/2026) :
/// `MediaRecorderImpl.startRecording` fait `throw new Exception("Audio-only
/// recording not implemented yet")` dès que la piste vidéo est nulle —
/// l'enregistrement AUDIO SEUL n'existe pas. Le démarrage levait toujours,
/// `demarrer()` rendait faux, et l'appel continuait sans trace :
/// `call_recording` restait vide sans qu'aucune erreur ne remonte.
///
/// La vraie voie branche un `AudioTrackSink` sur la piste locale (micro de
/// l'agent) ET sur la piste distante (voix du correspondant), encode deux AAC, et
/// le serveur les mélange. Tout le natif est dans `AppelEnregistreur.kt` ; ce
/// fichier n'en est que la façade Dart.
///
/// ⚠️ **DEUX PISTES, ATTACHÉES À DEUX MOMENTS.** La piste locale existe dès le
/// décrochage ; la DISTANTE n'arrive qu'après la négociation WebRTC. D'où
/// [attacherDistant], appelé séparément quand le flux distant apparaît.
///
/// ⚠️ **AUCUNE ANNONCE N'EST FAITE AU CORRESPONDANT** — décision explicite du
/// user (20/08/2026). Ni tonalité, ni message, ni indicateur de son côté.
///
/// ⚠️ **Singleton** : un enregistrement appartient à un APPEL, pas à un écran.
class EnregistreurAppel {
  EnregistreurAppel._();
  static final EnregistreurAppel instance = EnregistreurAppel._();

  static const _canal = MethodChannel("alanya/enregistrement");

  /// L'appel en cours d'enregistrement, ou nul. Sert de garde de ré-entrée :
  /// `accept` peut être rejoué (reconnexion, transfert) et deux enregistreurs
  /// sur le même appel se disputeraient les mêmes pistes.
  String? _callId;
  DateTime? _debut;
  bool _distantAttache = false;

  bool get enCours => _callId != null;
  String? get callIdEnCours => _callId;

  /// Démarre l'enregistrement de la voix de l'agent (piste locale). Rend faux si
  /// le support ne le permet pas — l'appel se déroule alors normalement, sans
  /// trace.
  ///
  /// ⚠️ **Ne lève JAMAIS.** Un enregistrement qui échoue ne doit pas faire
  /// échouer un décrochage : l'appel est ce qui compte, la trace est un
  /// supplément.
  Future<bool> demarrer(String callId, String localTrackId) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (_callId == callId) return true;
    if (_callId != null) await _abandonner();
    try {
      final ok =
          await _canal.invokeMethod<bool>("demarrer", {
            "callId": callId,
            "localTrackId": localTrackId,
          }) ??
          false;
      if (!ok) return false;
      _callId = callId;
      _debut = DateTime.now();
      _distantAttache = false;
      debugPrint("[EnregistreurAppel] démarré sur $callId");
      return true;
    } catch (e) {
      debugPrint("[EnregistreurAppel] démarrage impossible : $e");
      return false;
    }
  }

  /// Branche la voix du correspondant dès que sa piste est disponible.
  /// Idempotent : ne rebranche pas si c'est déjà fait. À appeler quand le flux
  /// distant apparaît côté mesh.
  Future<void> attacherDistant(String remoteTrackId) async {
    if (_callId == null || _distantAttache) return;
    try {
      await _canal.invokeMethod("attacherDistant", {
        "remoteTrackId": remoteTrackId,
      });
      _distantAttache = true;
      debugPrint("[EnregistreurAppel] voix distante branchée");
    } catch (e) {
      debugPrint("[EnregistreurAppel] attacherDistant : $e");
    }
  }

  /// Arrête et rend les CHEMINS des deux fichiers, ou `null` si rien
  /// d'exploitable. Les fichiers ne sont PAS effacés ici : c'est l'appelant qui
  /// s'en charge, une fois le dépôt confirmé par le serveur.
  ///
  /// ⚠️ **LES DEUX PISTES SONT EXIGÉES** (garantie posée côté natif) : une seule
  /// ne prouve rien et induirait en erreur celui qui l'écoute.
  Future<FichiersAppel?> arreter() async {
    if (_callId == null) return null;
    final debut = _debut ?? DateTime.now();
    _callId = null;
    _debut = null;
    _distantAttache = false;

    Map<dynamic, dynamic>? chemins;
    try {
      chemins = await _canal.invokeMethod<Map<dynamic, dynamic>>("arreter");
    } catch (e) {
      debugPrint("[EnregistreurAppel] arrêt : $e");
      return null;
    }
    final cheminAgent = chemins?["agent"] as String?;
    final cheminClient = chemins?["client"] as String?;
    if (cheminAgent == null || cheminClient == null) {
      debugPrint("[EnregistreurAppel] piste manquante — rien à envoyer");
      return null;
    }
    return (
      agent: cheminAgent,
      client: cheminClient,
      dureeMs: DateTime.now().difference(debut).inMilliseconds,
    );
  }

  /// Abandonne sans rien rendre : appel raccroché avant d'avoir commencé,
  /// démarrage raté, ou changement d'appel.
  Future<void> _abandonner() async {
    _callId = null;
    _debut = null;
    _distantAttache = false;
    try {
      await _canal.invokeMethod("abandonner");
    } catch (_) {}
  }
}
