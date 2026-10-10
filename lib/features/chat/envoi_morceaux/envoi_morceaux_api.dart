import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
import '../../../core/authed_api.dart';
import '../../../core/server_config.dart';

/// Les routes `/api/media/envois` (backend, cours chapitre 42).
///
/// ⚠️ DEUX JETONS, DEUX USAGES. Réserver et programmer la publication parlent
/// AU NOM DU COMPTE : jeton d'accès, par [AuthedApi]. Lire l'état, relancer,
/// abandonner se font avec le JETON D'ENVOI, qui n'ouvre que cet envoi et
/// survit aux 15 minutes du jeton d'accès — c'est lui qu'Android présente,
/// application fermée.
class ReservationEnvoi {
  const ReservationEnvoi({
    required this.id,
    required this.jeton,
    required this.tailleMorceau,
    required this.nbMorceaux,
    required this.mediaId,
  });

  final String id;
  final String jeton;
  final int tailleMorceau;
  final int nbMorceaux;

  /// L'identifiant que portera le média : celui de l'envoi. Il entre dans le
  /// descripteur chiffré AVANT que le fichier soit arrivé.
  final String mediaId;

  factory ReservationEnvoi.depuisJson(Map<String, dynamic> j) => ReservationEnvoi(
        id: j['id'] as String,
        jeton: j['jeton'] as String,
        tailleMorceau: (j['tailleMorceau'] as num).toInt(),
        nbMorceaux: (j['nbMorceaux'] as num).toInt(),
        mediaId: (j['mediaId'] ?? j['id']) as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'jeton': jeton,
        'tailleMorceau': tailleMorceau,
        'nbMorceaux': nbMorceaux,
        'mediaId': mediaId,
      };
}

/// Ce que le serveur dit d'un envoi (`GET …/envois/:id`, et la réponse de
/// chaque morceau).
class EtatEnvoiServeur {
  const EtatEnvoiServeur({
    required this.termine,
    required this.manquants,
    this.publication,
    this.messageId,
  });

  final bool termine;
  final List<int> manquants;

  /// `null` (rien de programmé), `attente`, `en_cours`, `publie`, `refus:<MOTIF>`.
  final String? publication;
  final String? messageId;

  bool get publie => publication == 'publie';
  bool get refuse => publication?.startsWith('refus:') ?? false;

  factory EtatEnvoiServeur.depuisJson(Map<String, dynamic> j) {
    final p = j['publication'];
    return EtatEnvoiServeur(
      termine: j['termine'] == true || j['statut'] == 'termine',
      manquants: [
        for (final m in (j['manquants'] as List? ?? const [])) (m as num).toInt(),
      ],
      publication: p is Map ? p['etat'] as String? : null,
      messageId: p is Map ? p['messageId'] as String? : null,
    );
  }
}

class EnvoiMorceauxApi {
  EnvoiMorceauxApi(this._authed, {String? base, http.Client? client})
      : _base = base ?? ServerConfig.apiBase,
        _client = client ?? http.Client();

  final AuthedApi _authed;
  final String _base;
  final http.Client _client;

  String get base => _base;

  /// Réserve l'envoi d'un fichier CHIFFRÉ de [taille] octets.
  Future<ReservationEnvoi> reserver({
    required int taille,
    required String empreinteHex,
    int? durationMs,
  }) async {
    final r = await _authed.post('/api/media/envois', {
      'taille': taille,
      // Nom et type neutres : les vrais vivent dans l'enveloppe chiffrée.
      'nom': 'chiffre.bin',
      'mime': 'application/octet-stream',
      'chiffre': true,
      'empreinte': empreinteHex,
      if (durationMs != null) 'durationMs': durationMs,
    });
    return ReservationEnvoi.depuisJson(r);
  }

  /// Confie au serveur le message à publier quand le fichier sera arrivé.
  /// Rend l'état de la publication (`attente`, ou `publie` si le fichier
  /// était déjà là).
  Future<String?> programmer(String id, Map<String, dynamic> publication) async {
    final r = await _authed.post('/api/media/envois/$id/publication', publication);
    return r['etat'] as String?;
  }

  Future<EtatEnvoiServeur> etat(String id, String jeton) =>
      _avecJeton('GET', '/api/media/envois/$id', jeton);

  /// Le filet : relance l'assemblage ou la publication restés en attente.
  Future<EtatEnvoiServeur> terminer(String id, String jeton) =>
      _avecJeton('POST', '/api/media/envois/$id/terminer', jeton);

  Future<void> abandonner(String id, String jeton) async {
    try {
      await _avecJeton('DELETE', '/api/media/envois/$id', jeton);
    } on ApiException catch (e) {
      // Déjà effacé (expiré, ou abandonné deux fois) : le but est atteint.
      if (e.statusCode != 404) rethrow;
    }
  }

  Future<EtatEnvoiServeur> _avecJeton(String methode, String chemin, String jeton) async {
    final req = http.Request(methode, Uri.parse('$_base$chemin'))
      ..headers['X-Envoi-Jeton'] = jeton;
    final rep = await http.Response.fromStream(
        await _client.send(req).timeout(ApiClient.delaiReponse));
    final corps = rep.body.isEmpty ? <String, dynamic>{} : jsonDecode(rep.body);
    if (rep.statusCode >= 400) {
      final err = corps is Map ? corps['error'] : null;
      throw ApiException(
        rep.statusCode,
        err is Map ? '${err['message']}' : 'Erreur ${rep.statusCode}',
        err is Map ? err['code'] as String? : null,
      );
    }
    return EtatEnvoiServeur.depuisJson(corps as Map<String, dynamic>);
  }
}
