import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/downloader_io.dart';
import '../../../core/server_config.dart';
import '../../../core/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/conversation.dart';
import '../../chat/chat_repository.dart';
import '../export_medias_repository.dart';

/// L'ÉCRAN D'EXPORTATION DES MÉDIAS.
///
/// Trois questions, dans l'ordre où on se les pose : QUELLES discussions, QUELS
/// médias, QUELLE période. Puis un décompte — combien de fichiers, quel poids —
/// avant de s'engager.
///
/// 🔴 LE DÉCOMPTE N'EST PAS UN ORNEMENT. Sans lui, on lance un export sans
/// savoir si l'on demande quarante mégaoctets ou six gigaoctets — et sur un
/// forfait mobile, on s'en aperçoit à la facture. Il est recalculé à chaque
/// changement de critère, et c'est lui qui décide si le bouton est actionnable.
class ExportMediasScreen extends StatefulWidget {
  const ExportMediasScreen({super.key});

  @override
  State<ExportMediasScreen> createState() => _ExportMediasScreenState();
}

class _ExportMediasScreenState extends State<ExportMediasScreen> {
  /// Le décompte suit la frappe : on attend une pause avant d'interroger.
  static const _reposAvantCalcul = Duration(milliseconds: 350);

  List<Conversation> _discussions = const [];
  bool _toutesDiscussions = true;
  final Set<String> _choisies = <String>{};
  String _recherche = '';

  final Set<String> _familles = ExportMediasRepository.familles.toSet();
  DateTime? _du;
  DateTime? _au;

  ChiffrageExport? _chiffrage;
  bool _calcule = false;
  bool _telecharge = false;
  double? _progression;

  /// Numéro de la demande en cours.
  ///
  /// ⚠️ UNE RÉPONSE EN RETARD NE DOIT PAS ÉCRIRE. On coche quatre types de
  /// médias d'affilée : rien ne garantit que les réponses reviennent dans
  /// l'ordre, et celle des critères abandonnés afficherait son décompte sous
  /// les critères actuels. Seule la dernière a le droit d'écrire.
  int _demande = 0;

  @override
  void initState() {
    super.initState();
    _chargerDiscussions();
    _relancerCalcul();
  }

  Future<void> _chargerDiscussions() async {
    try {
      final liste = await context.read<ChatRepository>().listConversations();
      if (!mounted) return;
      setState(() => _discussions = liste);
    } catch (_) {
      // Sans la liste, « toutes mes discussions » reste possible : l'écran ne
      // devient pas inutilisable parce qu'un chargement a échoué.
    }
  }

  CriteresExport get _criteres => CriteresExport(
        conversations: _toutesDiscussions ? const [] : _choisies.toList(),
        familles: _familles.toList(),
        du: _du,
        au: _au,
      );

  void _relancerCalcul() {
    final criteres = _criteres;
    if (!criteres.valide || (!_toutesDiscussions && _choisies.isEmpty)) {
      setState(() {
        _chiffrage = null;
        _calcule = false;
      });
      return;
    }
    setState(() => _calcule = true);
    final mien = ++_demande;
    Future<void>.delayed(_reposAvantCalcul, () async {
      if (!mounted || _demande != mien) return;
      try {
        final r = await context.read<ExportMediasRepository>().chiffrer(criteres);
        if (!mounted || _demande != mien) return;
        setState(() {
          _chiffrage = r;
          _calcule = false;
        });
      } catch (_) {
        if (!mounted || _demande != mien) return;
        setState(() {
          _chiffrage = null;
          _calcule = false;
        });
      }
    });
  }

  Future<void> _exporter() async {
    final t = AppLocalizations.of(context);
    final chiffrage = _chiffrage;
    if (chiffrage == null || chiffrage.fichiers == 0 || chiffrage.tropGros) return;

    final jeton = await context.read<TokenStorage>().accessToken;
    if (!mounted) return;

    final chemin = context.read<ExportMediasRepository>().chemin(_criteres);
    /*
     * ⚠️ LE JETON VOYAGE DANS L'URL, faute d'alternative : le téléchargeur écrit
     * dans le stockage public par MediaStore et ne porte pas d'en-tête choisi.
     * C'est le même mécanisme que les médias ouverts depuis une discussion, et
     * le serveur ne l'accepte que pour un jeton d'accès valide.
     */
    final url = '${ServerConfig.apiBase}$chemin${jeton == null ? '' : '&token=$jeton'}';
    final jour = DateTime.now().toIso8601String().substring(0, 10);

    setState(() {
      _telecharge = true;
      _progression = null;
    });
    try {
      final chemin = await downloadUrl(
        url,
        'alanya-medias-$jour.zip',
        surProgression: (f) {
          if (mounted) setState(() => _progression = f);
        },
      );
      if (!mounted) return;
      _avis(chemin == null ? t.get('exp_echec') : t.get('exp_termine'));
    } catch (_) {
      if (mounted) _avis(t.get('exp_echec'));
    } finally {
      if (mounted) {
        setState(() {
          _telecharge = false;
          _progression = null;
        });
      }
    }
  }

  void _avis(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  /// Le sélecteur de date ET d'heure, en deux temps.
  ///
  /// ⚠️ L'HEURE COMPTE AUTANT QUE LE JOUR. « Ce matin entre 9 h et 9 h 30 »
  /// est une demande réelle — cinquante fichiers reçus en vingt minutes — et un
  /// sélecteur de date seule obligerait à exporter la journée entière.
  Future<DateTime?> _choisirInstant(DateTime? actuel) async {
    final maintenant = DateTime.now();
    final jour = await showDatePicker(
      context: context,
      initialDate: actuel ?? maintenant,
      firstDate: DateTime(2020),
      lastDate: maintenant.add(const Duration(days: 1)),
    );
    if (jour == null || !mounted) return null;
    final heure = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actuel ?? maintenant),
    );
    if (heure == null) return null;
    return DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);
  }

  void _raccourci(int? jours) {
    setState(() {
      if (jours == null) {
        _du = null;
        _au = null;
      } else {
        final fin = DateTime.now();
        _du = fin.subtract(Duration(days: jours));
        _au = fin;
      }
    });
    _relancerCalcul();
  }

  List<Conversation> get _visibles {
    final q = _recherche.trim().toLowerCase();
    if (q.isEmpty) return _discussions;
    /*
     * LE NOM OU LE NUMÉRO. Une conversation à deux n'a pas de nom à elle : il
     * vient de son correspondant. Ne chercher que dans les titres priverait de
     * la seule façon fiable de retrouver quelqu'un qu'on n'a pas enregistré.
     */
    return _discussions.where((c) {
      final titre = (c.title ?? '').toLowerCase();
      if (titre.contains(q)) return true;
      return c.members.any((m) =>
          m.displayName.toLowerCase().contains(q) ||
          m.publicNumber.toLowerCase().contains(q));
    }).toList();
  }

  String _nomDe(Conversation c) {
    if (c.isGroup) return c.title ?? '';
    // En tête-à-tête, le nom de l'autre — pas le titre, qui est vide.
    final autre = c.members.isNotEmpty ? c.members.first : null;
    return c.title?.isNotEmpty == true
        ? c.title!
        : (autre?.displayName ?? '');
  }

  String _instantLisible(DateTime? d) {
    if (d == null) return '—';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chiffrage = _chiffrage;
    final inverse = _criteres.periodeInversee;
    final pretAPartir = chiffrage != null &&
        chiffrage.fichiers > 0 &&
        !chiffrage.tropGros &&
        !_calcule &&
        !_telecharge;

    final libelles = <String, String>{
      'photo': t.get('exp_photo'),
      'video': t.get('exp_video'),
      'audio': t.get('exp_audio'),
      'document': t.get('exp_document'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(t.get('exp_titre'))),
      body: ListView(
        // Les marges suivent celles des autres écrans de réglages : une page
        // qui respire différemment de ses voisines se lit comme un morceau
        // rapporté.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(t.get('exp_sub'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),

          // ⚠️ DIT D'EMBLÉE, ET NON EN NOTE DE BAS DE PAGE : « seuls les médias
          // reçus » change entièrement ce qu'on attend de l'archive. Le
          // découvrir après un téléchargement de deux gigaoctets serait une
          // perte de temps qu'une phrase évite.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            child: Text(t.get('exp_avert_recus'), style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 20),

          // ── 1. Les discussions ─────────────────────────────────────────
          _Etape(numero: 1, titre: t.get('exp_etape_disc')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Choix(
                  texte: t.get('exp_toutes_disc'),
                  actif: _toutesDiscussions,
                  onTap: () {
                    setState(() => _toutesDiscussions = true);
                    _relancerCalcul();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Choix(
                  texte: t.get('exp_choisir_disc'),
                  badge: _choisies.isEmpty ? null : '${_choisies.length}',
                  actif: !_toutesDiscussions,
                  onTap: () {
                    setState(() => _toutesDiscussions = false);
                    _relancerCalcul();
                  },
                ),
              ),
            ],
          ),
          if (!_toutesDiscussions) ...[
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: t.get('exp_rechercher'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _recherche = v),
            ),
            if (_choisies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.get('exp_selection').replaceAll('{n}', '${_choisies.length}'),
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(_choisies.clear);
                        _relancerCalcul();
                      },
                      child: Text(t.get('exp_tout_effacer')),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            // Hauteur bornée : trois cents discussions pousseraient le bouton
            // d'export hors de l'écran, et l'on ne saurait plus quoi faire.
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(11),
              ),
              child: _visibles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t.get('exp_aucune_disc'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _visibles.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: theme.dividerColor,
                      ),
                      itemBuilder: (_, i) {
                        final c = _visibles[i];
                        final coche = _choisies.contains(c.id);
                        return CheckboxListTile(
                          dense: true,
                          value: coche,
                          title: Text(
                            _nomDe(c),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (_) {
                            setState(() {
                              if (coche) {
                                _choisies.remove(c.id);
                              } else {
                                _choisies.add(c.id);
                              }
                            });
                            _relancerCalcul();
                          },
                        );
                      },
                    ),
            ),
          ],
          const SizedBox(height: 20),

          // ── 2. Les types de médias ─────────────────────────────────────
          _Etape(numero: 2, titre: t.get('exp_etape_types')),
          const SizedBox(height: 10),
          // « Tous » est un bouton, pas une consigne : tout cocher demandait
          // quatre gestes, et tout décocher quatre autres.
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  if (_familles.length == ExportMediasRepository.familles.length) {
                    _familles.clear();
                  } else {
                    _familles
                      ..clear()
                      ..addAll(ExportMediasRepository.familles);
                  }
                });
                _relancerCalcul();
              },
              child: Text(t.get('exp_tous_types')),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ExportMediasRepository.familles.map((f) {
              final coche = _familles.contains(f);
              return FilterChip(
                label: Text(libelles[f] ?? f),
                selected: coche,
                onSelected: (_) {
                  setState(() {
                    if (coche) {
                      _familles.remove(f);
                    } else {
                      _familles.add(f);
                    }
                  });
                  _relancerCalcul();
                },
              );
            }).toList(),
          ),
          if (_familles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.get('exp_type_requis'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),

          // ── 3. La période ──────────────────────────────────────────────
          _Etape(numero: 3, titre: t.get('exp_etape_periode')),
          const SizedBox(height: 10),
          // Les raccourcis d'abord : « les 30 derniers jours » est la demande
          // la plus fréquente, et la composer à la main chaque mois est une
          // corvée que deux mots évitent.
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _Raccourci(texte: t.get('exp_raccourci_7j'), onTap: () => _raccourci(7)),
              _Raccourci(texte: t.get('exp_raccourci_30j'), onTap: () => _raccourci(30)),
              _Raccourci(texte: t.get('exp_raccourci_an'), onTap: () => _raccourci(365)),
              _Raccourci(texte: t.get('exp_raccourci_tout'), onTap: () => _raccourci(null)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Instant(
                  etiquette: t.get('exp_du'),
                  valeur: _instantLisible(_du),
                  onTap: () async {
                    final d = await _choisirInstant(_du);
                    if (d == null) return;
                    setState(() => _du = d);
                    _relancerCalcul();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Instant(
                  etiquette: t.get('exp_au'),
                  valeur: _instantLisible(_au),
                  onTap: () async {
                    final d = await _choisirInstant(_au);
                    if (d == null) return;
                    setState(() => _au = d);
                    _relancerCalcul();
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              inverse ? t.get('exp_periode_inverse') : t.get('exp_periode_libre'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: inverse ? theme.colorScheme.error : null,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // ── Le résumé, puis le départ ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _calcule
                      ? t.get('exp_calcul')
                      : chiffrage == null || chiffrage.fichiers == 0
                          ? t.get('exp_rien')
                          : chiffrage.tropGros
                              ? t.get('exp_trop_gros')
                              : t
                                  .get('exp_resume')
                                  .replaceAll('{n}', '${chiffrage.fichiers}')
                                  .replaceAll('{t}', tailleLisible(chiffrage.octets)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: chiffrage?.tropGros == true ? theme.colorScheme.error : null,
                  ),
                ),
                if (_telecharge) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progression),
                  const SizedBox(height: 6),
                  Text(
                    _progression == null
                        ? t.get('exp_encours')
                        : t.get('exp_lance'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: pretAPartir ? _exporter : null,
                  child: Text(t.get('exp_lancer')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le numéro d'étape encode une SÉQUENCE réelle — on choisit les discussions,
/// puis les types, puis la période — et non une décoration.
class _Etape extends StatelessWidget {
  const _Etape({required this.numero, required this.titre});

  final int numero;
  final String titre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$numero',
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(titre, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _Choix extends StatelessWidget {
  const _Choix({
    required this.texte,
    required this.actif,
    required this.onTap,
    this.badge,
  });

  final String texte;
  final bool actif;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: actif ? theme.colorScheme.primary : null,
          border: Border.all(
            color: actif ? theme.colorScheme.primary : theme.dividerColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                texte,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: actif ? theme.colorScheme.onPrimary : null,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: actif ? theme.colorScheme.onPrimary : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Raccourci extends StatelessWidget {
  const _Raccourci({required this.texte, required this.onTap});

  final String texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(texte), onPressed: onTap);
  }
}

class _Instant extends StatelessWidget {
  const _Instant({
    required this.etiquette,
    required this.valeur,
    required this.onTap,
  });

  final String etiquette;
  final String valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiquette, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              valeur,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
