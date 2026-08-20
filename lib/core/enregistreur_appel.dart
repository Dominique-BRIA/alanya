import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

/// Le résultat d'un enregistrement : les DEUX pistes, et la durée.
typedef PistesAppel = ({Uint8List agent, Uint8List client, int dureeMs});

/// Enregistre une conversation d'agent, sur autorisation du serveur.
///
/// 🔴 **DEUX PISTES, PARCE QUE LE GREFFON N'EN SAIT PAS FAIRE UNE.** Vérifié
/// dans le code Android de `flutter_webrtc` avant d'écrire quoi que ce soit —
/// `GetUserMediaImpl.startRecordingToFile` choisit `inputSamplesInterceptor` OU
/// `outputSamplesInterceptor`, jamais les deux, et `RecorderAudioChannel` n'a
/// que `INPUT` et `OUTPUT`. Un seul enregistreur ne capterait donc QUE la voix
/// de l'agent, ou QUE celle du correspondant : inutilisable.
///
/// On lance donc DEUX enregistreurs en parallèle et le serveur mélange. C'est
/// ce qui évite de maintenir un fork de `flutter_webrtc`, dépendance critique
/// dont chaque montée de version deviendrait un chantier.
///
/// ⚠️ **AUCUNE ANNONCE N'EST FAITE AU CORRESPONDANT** — décision explicite du
/// user (20/08/2026). Ni tonalité, ni message, ni indicateur de son côté. Écrit
/// ici pour que ce soit une décision tracée et non un oubli.
///
/// ⚠️ **Singleton**, comme `RingtoneService` et `EnvoiMediaStore` : un
/// enregistrement appartient à un APPEL, pas à un écran. Le lier à une vue le
/// ferait mourir dès que l'agent ouvre la conversation pendant l'appel — c'est
/// exactement la leçon du 17/08/2026 sur la file d'envois.
class EnregistreurAppel {
  EnregistreurAppel._();
  static final EnregistreurAppel instance = EnregistreurAppel._();

  MediaRecorder? _agent;
  MediaRecorder? _client;
  String? _cheminAgent;
  String? _cheminClient;
  DateTime? _debut;

  /// L'appel en cours d'enregistrement, ou nul. Sert de garde de ré-entrée :
  /// `accept` peut être rejoué (reconnexion, transfert) et deux enregistreurs
  /// sur le même appel se disputeraient le même intercepteur natif.
  String? _callId;

  bool get enCours => _callId != null;
  String? get callIdEnCours => _callId;

  /// Démarre les deux pistes. Rend faux si le support ne le permet pas — dans
  /// ce cas l'appel se déroule normalement, simplement sans enregistrement.
  ///
  /// ⚠️ **Ne lève JAMAIS.** Un enregistrement qui échoue ne doit pas faire
  /// échouer un décrochage : l'appel est ce qui compte, la trace est un
  /// supplément.
  Future<bool> demarrer(String callId) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    // Déjà en cours sur CET appel : rien à faire, et surtout pas relancer.
    if (_callId == callId) return true;
    // En cours sur un AUTRE appel : on referme, sinon les deux enregistreurs
    // se disputeraient l'intercepteur natif, qui est unique par canal.
    if (_callId != null) await _abandonner();

    try {
      final dir = await getTemporaryDirectory();
      final base =
          "${dir.path}/appel-$callId-${DateTime.now().millisecondsSinceEpoch}";
      _cheminAgent = "$base-agent.aac";
      _cheminClient = "$base-client.aac";

      _agent = MediaRecorder();
      await _agent!.start(
        _cheminAgent!,
        audioChannel: RecorderAudioChannel.INPUT,
      );

      _client = MediaRecorder();
      await _client!.start(
        _cheminClient!,
        audioChannel: RecorderAudioChannel.OUTPUT,
      );

      _debut = DateTime.now();
      _callId = callId;
      debugPrint("[EnregistreurAppel] démarré sur $callId");
      return true;
    } catch (e) {
      debugPrint("[EnregistreurAppel] démarrage impossible : $e");
      // ⚠️ Un démarrage à MOITIÉ fait est le pire cas : la piste de l'agent
      // tournerait seule et produirait un enregistrement trompeur, où le
      // correspondant paraîtrait n'avoir rien dit. On referme tout.
      await _abandonner();
      return false;
    }
  }

  /// Arrête et rend les deux pistes, ou `null` si rien d'exploitable.
  ///
  /// ⚠️ **LES DEUX PISTES SONT EXIGÉES.** Une seule ne vaut rien : un
  /// enregistrement où l'on n'entend qu'une voix ne prouve rien et induirait en
  /// erreur celui qui l'écoute. Mieux vaut ne rien rendre.
  Future<PistesAppel?> arreter() async {
    if (_callId == null) return null;
    final debut = _debut ?? DateTime.now();
    final cheminAgent = _cheminAgent;
    final cheminClient = _cheminClient;

    try {
      await _agent?.stop();
    } catch (_) {}
    try {
      await _client?.stop();
    } catch (_) {}
    _agent = null;
    _client = null;
    _callId = null;
    _debut = null;
    _cheminAgent = null;
    _cheminClient = null;

    final agent = await _lireEtEffacer(cheminAgent);
    final client = await _lireEtEffacer(cheminClient);
    if (agent == null || client == null) {
      debugPrint("[EnregistreurAppel] piste manquante — rien à envoyer");
      return null;
    }
    return (
      agent: agent,
      client: client,
      dureeMs: DateTime.now().difference(debut).inMilliseconds,
    );
  }

  /// Abandonne sans rien rendre : appel raccroché avant d'avoir commencé,
  /// démarrage raté, ou changement d'appel.
  Future<void> _abandonner() async {
    try {
      await _agent?.stop();
    } catch (_) {}
    try {
      await _client?.stop();
    } catch (_) {}
    _agent = null;
    _client = null;
    await _lireEtEffacer(_cheminAgent);
    await _lireEtEffacer(_cheminClient);
    _cheminAgent = null;
    _cheminClient = null;
    _callId = null;
    _debut = null;
  }

  /// Lit un fichier puis l'efface. Le fichier temporaire ne doit jamais
  /// survivre : ce sont des minutes d'audio, et personne ne les nettoierait.
  Future<Uint8List?> _lireEtEffacer(String? chemin) async {
    if (chemin == null) return null;
    try {
      final f = File(chemin);
      if (!await f.exists()) return null;
      final octets = await f.readAsBytes();
      try {
        await f.delete();
      } catch (_) {}
      return octets.isEmpty ? null : octets;
    } catch (_) {
      return null;
    }
  }
}
