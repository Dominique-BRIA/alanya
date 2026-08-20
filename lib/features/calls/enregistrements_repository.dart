import 'dart:math';

import '../../core/authed_api.dart';
import '../../core/enregistreur_appel.dart';
import '../media/media_repository.dart';

/// Dépôt d'un enregistrement de conversation agent ↔ client.
///
/// ⚠️ Le contrat vit côté serveur (`src/app/api/call-recordings/route.ts`).
///
/// 🔴 **DEUX PISTES, PUIS LE SERVEUR MÉLANGE.** Le greffon `flutter_webrtc` ne
/// sait enregistrer qu'un côté à la fois — voir `EnregistreurAppel`. On
/// téléverse donc le micro et le distant séparément.
class EnregistrementsRepository {
  EnregistrementsRepository(this._api, this._medias);
  final AuthedApi _api;
  final MediaRepository _medias;

  /// Téléverse les deux pistes puis les rattache à un enregistrement.
  ///
  /// 🔴 **LA CLÉ D'ENVOI EST POSÉE ICI ET UNE SEULE FOIS.** Elle rend le dépôt
  /// idempotent : un réessai après échec réseau réutilise la même, et le serveur
  /// rend l'enregistrement déjà déposé au lieu d'en créer un second. La
  /// regénérer à chaque tentative annulerait toute la garantie.
  ///
  /// ⚠️ **L'ORDRE COMPTE** : les deux médias sont téléversés AVANT le dépôt. Si
  /// le second échoue, rien n'est rattaché — mieux vaut deux médias orphelins,
  /// que le serveur pourra purger, qu'un enregistrement qui référence une piste
  /// inexistante et se croit complet.
  Future<void> deposer({
    String? callId,
    required int companyId,
    required PistesAppel pistes,
  }) async {
    final cle = _fabriquerCle();
    final agent = await _medias.upload(
      pistes.agent,
      "appel-$cle-agent.aac",
      "audio/aac",
      durationMs: pistes.dureeMs,
    );
    final client = await _medias.upload(
      pistes.client,
      "appel-$cle-client.aac",
      "audio/aac",
      durationMs: pistes.dureeMs,
    );
    await _api.post("/api/call-recordings", {
      if (callId != null) "callId": callId,
      "companyId": companyId,
      "mediaAgentId": agent.id,
      "mediaClientId": client.id,
      "dureeMs": pistes.dureeMs,
      "cleEnvoi": cle,
    });
  }

  String _fabriquerCle() {
    final alea = Random();
    final suffixe = List.generate(
      8,
      (_) => alea.nextInt(36).toRadixString(36),
    ).join();
    return "ap-${DateTime.now().millisecondsSinceEpoch}-$suffixe";
  }
}
