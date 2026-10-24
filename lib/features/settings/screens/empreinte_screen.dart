import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/api_client.dart';
import '../../../core/authed_api.dart';
import '../../../core/empreinte_saisie.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';

/// VÉRIFIER UNE EMPREINTE NUMÉRIQUE (24/10/2026, demande du user).
///
/// Toute copie d'un document sensible sortie d'Alanya porte une empreinte de
/// 32 caractères, écrite aux bords du document et dans ses propriétés. Saisie
/// ici, elle dit qui a fait sortir la copie, quand, depuis quel appareil, et
/// qui avait envoyé le document. Tout compte peut faire la recherche
/// (décision du user) ; le serveur ne renvoie jamais l'adresse IP.
///
/// La saisie se fait en blocs de quatre, comme sur le document
/// (`FormateurEmpreinte`) : on recopie « 3F9A 0C1E … » sans se perdre.
class EmpreinteScreen extends StatefulWidget {
  const EmpreinteScreen({super.key});

  @override
  State<EmpreinteScreen> createState() => _EmpreinteScreenState();
}

class _EmpreinteScreenState extends State<EmpreinteScreen> {
  final _champ = TextEditingController();
  bool _enCours = false;
  String? _erreur;
  Map<String, dynamic>? _resultat;

  static const _chasseFixe = TextStyle(
    fontFamily: 'monospace',
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  Future<void> _coller() async {
    final presse = await Clipboard.getData(Clipboard.kTextPlain);
    final texte = presse?.text ?? '';
    final valeur = FormateurEmpreinte().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: texte,
        selection: TextSelection.collapsed(offset: texte.length),
      ),
    );
    setState(() {
      _champ.value = valeur;
      _erreur = null;
    });
  }

  Future<void> _rechercher() async {
    final code = Empreinte.pourServeur(_champ.text);
    if (code == null) {
      setState(() {
        _erreur = tr(context, 'emp_invalide');
        _resultat = null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final api = context.read<AuthedApi>();
    final inconnue = tr(context, 'emp_inconnue');
    final invalide = tr(context, 'emp_invalide');
    final echec = tr(context, 'emp_echec');
    setState(() {
      _enCours = true;
      _erreur = null;
      _resultat = null;
    });
    try {
      final r = await api.get('/api/documents-sensibles/empreintes/$code');
      if (mounted) setState(() => _resultat = r);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _erreur = e.statusCode == 404
              ? inconnue
              : e.statusCode == 422
              ? invalide
              : echec,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _erreur = echec);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String _geste(String? code) => switch (code) {
    'TELECHARGEMENT' => tr(context, 'emp_g_telechargement'),
    'PARTAGE' => tr(context, 'emp_g_partage'),
    'TRANSFERT' => tr(context, 'emp_g_transfert'),
    _ => code ?? '—',
  };

  String _date(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} '
        '${deux(d.hour)}:${deux(d.minute)}';
  }

  /// « 67 64 15 99 · Pseudo », ou « Inconnu ».
  String _personne(Object? p) {
    if (p is! Map) return tr(context, 'emp_inconnu');
    final id = formatAlanyaId('${p['alanyaId'] ?? ''}');
    final nom = (p['nom'] as String?)?.trim() ?? '';
    return nom.isEmpty ? 'Alanya $id' : 'Alanya $id · $nom';
  }

  @override
  Widget build(BuildContext context) {
    final discret = themed(
      context,
      light: AlanyaColors.grey500,
      dark: AlanyaColors.craie2,
    );
    final accent = themed(
      context,
      light: AlanyaColors.terracotta,
      dark: AlanyaColors.terracottaNuit,
    );
    final r = _resultat;
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'emp_titre')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(context, 'emp_aide'), style: TextStyle(color: discret)),
          const SizedBox(height: 16),
          TextField(
            controller: _champ,
            inputFormatters: [FormateurEmpreinte()],
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            style: _chasseFixe.copyWith(fontSize: 17),
            // Huit blocs de quatre, plus sept espaces.
            maxLines: 2,
            minLines: 1,
            onChanged: (_) {
              if (_erreur != null) setState(() => _erreur = null);
            },
            onSubmitted: (_) => _rechercher(),
            decoration: InputDecoration(
              labelText: tr(context, 'emp_champ'),
              hintText: 'XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX',
              hintStyle: _chasseFixe.copyWith(fontSize: 15, color: discret),
              errorText: _erreur,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: tr(context, 'emp_coller'),
                icon: const Icon(Icons.content_paste),
                onPressed: _coller,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _enCours ? null : _rechercher,
            icon: _enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(tr(context, 'emp_rechercher')),
          ),
          if (r != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr(context, 'emp_resultat'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ligne(
                      tr(context, 'emp_champ'),
                      Empreinte.enBlocs('${r['empreinte'] ?? ''}'),
                      chasseFixe: true,
                    ),
                    _ligne(tr(context, 'emp_par'), _personne(r['utilisateur'])),
                    _ligne(
                      tr(context, 'emp_geste'),
                      _geste(r['geste'] as String?),
                    ),
                    _ligne(
                      tr(context, 'emp_date'),
                      _date(r['date'] as String?),
                    ),
                    _ligne(
                      tr(context, 'emp_appareil'),
                      (r['appareil'] as String?) ?? tr(context, 'emp_inconnu'),
                    ),
                    _ligne(
                      tr(context, 'emp_expediteur'),
                      _personne(r['expediteur']),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ligne(String titre, String valeur, {bool chasseFixe = false}) {
    final discret = themed(
      context,
      light: AlanyaColors.grey500,
      dark: AlanyaColors.craie2,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: TextStyle(fontSize: 12, color: discret)),
          const SizedBox(height: 2),
          SelectableText(
            valeur,
            style: chasseFixe
                ? _chasseFixe.copyWith(fontSize: 15)
                : const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
}
