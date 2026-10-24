import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/authed_api.dart';
import '../../core/downloader.dart';
import '../../core/infos_appareil.dart';
import '../../core/signature_document.dart';
import '../../services/e2ee/e2ee_media.dart';
import '../auth/auth_controller.dart';
import 'screens/media_gallery_viewer.dart' show nomPourEnregistrer;

/// FAIRE SORTIR UN DOCUMENT SENSIBLE (22/10/2026, revu le 24/10/2026).
///
/// Seul l'ENREGISTREMENT sort un document sensible de l'application : le
/// partage et le transfert, permis du 22 au 24/10, sont de nouveau bloqués
/// (user). La copie enregistrée est signée (`SignatureDocument` : texte aux
/// quatre bords, métadonnées, empreinte numérique) et le geste est noté par
/// le serveur avec l'empreinte (`document_consultation`).
///
/// Le contexte est lu à la construction ([SortieDocumentSensible.de]), avant
/// toute attente : la suite ne touche plus au `BuildContext`.
class SortieDocumentSensible {
  SortieDocumentSensible._(this._api, this._numero);

  factory SortieDocumentSensible.de(BuildContext context) =>
      SortieDocumentSensible._(
        context.read<AuthedApi>(),
        context.read<AuthController>().user?.publicNumber ?? '',
      );

  final AuthedApi _api;
  final String _numero;

  /// La copie signée de [clair] (le fichier déchiffré), au nom de qui la fait
  /// sortir. Ne lève pas pour un échec de signature (la copie sort telle
  /// quelle, `signee: false`) ; le geste est noté dans tous les cas.
  Future<CopieSignee> copie({
    required File clair,
    required DescripteurMedia d,
    required GesteSortie geste,
    String? convId,
    String? expediteurId,
  }) async {
    final signature = SignatureSortie.nouvelle(
      geste: geste,
      alanyaId: _numero,
      appareil: await InfosAppareil.marqueModele(),
      expediteurId: expediteurId,
      mediaId: d.id,
    );
    final copie = await SignatureDocument.signer(
      source: clair,
      nom: nomPourEnregistrer(d),
      mime: d.mime,
      signature: signature,
    );
    unawaited(_noter(signature, d, convId));
    return copie;
  }

  /// Enregistre la copie signée dans le dossier public Alanya. Rend le chemin
  /// (ou `null` en cas d'échec) et la copie.
  Future<({String? chemin, CopieSignee copie})> enregistrer({
    required File clair,
    required DescripteurMedia d,
    String? convId,
    String? expediteurId,
  }) async {
    final c = await copie(
      clair: clair,
      d: d,
      geste: GesteSortie.telechargement,
      convId: convId,
      expediteurId: expediteurId,
    );
    final chemin = await enregistrerOctets(await c.fichier.readAsBytes(), c.nom);
    return (chemin: chemin, copie: c);
  }

  /// La trace au serveur. Ne bloque jamais le geste : hors ligne, la copie
  /// garde ses métadonnées, seule la ligne serveur manque.
  Future<void> _noter(SignatureSortie s, DescripteurMedia d, String? convId) async {
    try {
      await _api.post('/api/documents-sensibles/consultations', {
        'mediaId': d.id,
        if (convId != null) 'convId': convId,
        'appareil': s.appareil,
        'action': s.geste.code,
        'codeTrace': s.code,
      });
    } catch (_) {}
  }
}
