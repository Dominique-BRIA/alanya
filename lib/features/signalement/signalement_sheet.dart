import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_snackbar.dart';
import '../../core/authed_api.dart';
import '../../l10n/app_localizations.dart';
import '../blocked/blocked_repository.dart';

/// Ce que l'on signale (18/11/2026).
sealed class CibleSignalement {
  const CibleSignalement();
}

/// Le message d'un autre. [extrait] : son texte, transmis seulement si le fil
/// est [chiffre] — le serveur ne peut pas le lire autrement.
class SignalerMessage extends CibleSignalement {
  const SignalerMessage({
    required this.messageId,
    required this.chiffre,
    this.extrait,
    this.auteurNumero,
  });
  final String messageId;
  final bool chiffre;
  final String? extrait;

  /// Le numéro de l'auteur, pour « Bloquer aussi ce compte ».
  final String? auteurNumero;
}

class SignalerCompte extends CibleSignalement {
  const SignalerCompte({required this.userId, this.numero});
  final String userId;
  final String? numero;
}

class SignalerGroupe extends CibleSignalement {
  const SignalerGroupe(this.convId);
  final String convId;
}

/// Une réponse de l'Assistant Alanya.
class SignalerReponseIa extends CibleSignalement {
  const SignalerReponseIa(this.aiMessageId);
  final String aiMessageId;
}

/*
 * 🔴 SIGNALER (18/11/2026, exigence du Play Store pour une messagerie et pour
 * l'IA générative) : un message, un compte, un groupe ou une réponse de
 * l'Assistant. Le signalement arrive dans la file de modération de la console
 * (`POST /api/signalements`, console › Signalements).
 *
 * ⚠️ DANS UN FIL CHIFFRÉ, LE SERVEUR NE LIT RIEN : le texte du SEUL message
 * signalé part avec le signalement, et la fenêtre le dit.
 *
 * Jumeau du web : `src/components/signalement.tsx`.
 */
class SignalementSheet extends StatefulWidget {
  const SignalementSheet({super.key, required this.cible});
  final CibleSignalement cible;

  static const motifs = [
    'harassment',
    'hate',
    'violence',
    'sexual',
    'scam',
    'spam',
    'impersonation',
    'other',
  ];

  static Future<void> ouvrir(BuildContext context, CibleSignalement cible) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SignalementSheet(cible: cible),
      );

  /// Le corps envoyé au serveur — à part pour être éprouvé seul.
  static Map<String, dynamic> corps(CibleSignalement cible, String motif, String note) {
    final c = <String, dynamic>{'motif': motif};
    if (note.trim().isNotEmpty) {
      final n = note.trim();
      c['note'] = n.length > 1000 ? n.substring(0, 1000) : n;
    }
    switch (cible) {
      case SignalerMessage m:
        c['cible'] = 'message';
        c['messageId'] = m.messageId;
        final extrait = m.extrait;
        if (m.chiffre && extrait != null && extrait.isNotEmpty) {
          c['extrait'] = extrait.length > 4000 ? extrait.substring(0, 4000) : extrait;
        }
      case SignalerCompte u:
        c['cible'] = 'user';
        c['userId'] = u.userId;
      case SignalerGroupe g:
        c['cible'] = 'group';
        c['convId'] = g.convId;
      case SignalerReponseIa r:
        c['cible'] = 'ia';
        c['aiMessageId'] = r.aiMessageId;
    }
    return c;
  }

  @override
  State<SignalementSheet> createState() => _SignalementSheetState();
}

class _SignalementSheetState extends State<SignalementSheet> {
  String? _motif;
  final _note = TextEditingController();
  bool _bloquer = false;
  bool _enCours = false;

  String? get _numeroABloquer => switch (widget.cible) {
        SignalerCompte u => u.numero,
        SignalerMessage m => m.auteurNumero,
        _ => null,
      };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _titre(BuildContext context) => tr(
        context,
        switch (widget.cible) {
          SignalerMessage() => 'sig_titre_message',
          SignalerCompte() => 'sig_titre_compte',
          SignalerGroupe() => 'sig_titre_groupe',
          SignalerReponseIa() => 'sig_titre_ia',
        },
      );

  Future<void> _envoyer() async {
    final motif = _motif;
    if (motif == null || _enCours) return;
    setState(() => _enCours = true);
    final api = context.read<AuthedApi>();
    final bloques = context.read<BlockedRepository>();
    final merci = tr(context, 'sig_merci');
    final deja = tr(context, 'sig_deja');
    final echec = tr(context, 'sig_echec');
    final nav = Navigator.of(context);
    try {
      await api.post('/api/signalements', SignalementSheet.corps(widget.cible, motif, _note.text));
      final numero = _numeroABloquer;
      if (_bloquer && numero != null && numero.isNotEmpty) {
        try {
          await bloques.blockUser(numero);
        } catch (_) {}
      }
      nav.pop();
      showAppSnackBar(merci);
    } on ApiException catch (e) {
      if (e.code == 'ALREADY_REPORTED') {
        nav.pop();
        showAppSnackBar(deja);
      } else {
        showAppSnackBar(echec);
      }
    } catch (_) {
      showAppSnackBar(echec);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = switch (widget.cible) {
      SignalerMessage m when m.chiffre => tr(context, 'sig_info_chiffre'),
      SignalerReponseIa() => tr(context, 'sig_info_ia'),
      _ => null,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_titre(context), style: Theme.of(context).textTheme.titleLarge),
              if (info != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(info,
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Text(tr(context, 'sig_motif'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              RadioGroup<String>(
                groupValue: _motif,
                onChanged: (v) => setState(() => _motif = v),
                child: Column(children: [
                  for (final m in SignalementSheet.motifs)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: m,
                      title: Text(tr(context, 'sig_m_$m')),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _note,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: tr(context, 'sig_note')),
              ),
              if (_numeroABloquer?.isNotEmpty == true)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _bloquer,
                  onChanged: (v) => setState(() => _bloquer = v ?? false),
                  title: Text(tr(context, 'sig_bloquer_aussi')),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                  onPressed: _motif == null || _enCours ? null : _envoyer,
                  icon: _enCours
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.flag_outlined),
                  label: Text(tr(context, 'sig_envoyer')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
