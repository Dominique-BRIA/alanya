import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/sonneries_livrees.dart';
import '../../../models/contact_list.dart';
import '../../../models/sonnerie.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../../settings/ringtones_repository.dart';
import '../contact_lists_repository.dart';

/// « Sonneries — <liste> » : les deux sons d'une liste, et l'ordre qui départage.
///
/// POURQUOI UN ÉCRAN, ET NON DEUX CHAMPS DANS L'ÉDITEUR. Les sons d'une liste ne
/// se règlent pas en la créant : on crée d'abord, on écoute ensuite. Surtout,
/// l'ORDRE DE PRIORITÉ ne concerne aucune liste en particulier — il les ordonne
/// toutes. Le loger dans l'éditeur de « Famille » aurait laissé croire qu'on
/// règle Famille, alors qu'on décide pour les quatre.
class SonneriesListeScreen extends StatefulWidget {
  const SonneriesListeScreen({
    super.key,
    required this.liste,
    required this.toutesLesListes,
  });

  final ListeContacts liste;

  /// Toutes les listes du compte, dans l'ordre que le serveur a rendu.
  ///
  /// ⚠️ INDISPENSABLE, et pas seulement pour l'affichage : le serveur refuse un
  /// réordonnancement qui ne les cite pas TOUTES (422 `ORDRE_INCOMPLET`).
  final List<ListeContacts> toutesLesListes;

  @override
  State<SonneriesListeScreen> createState() => _SonneriesListeScreenState();
}

class _SonneriesListeScreenState extends State<SonneriesListeScreen> {
  late String? _sonAppel = widget.liste.ringtone;
  late String? _sonMessage = widget.liste.ringtoneMessage;

  /// L'ordre affiché, manipulé par glissement. Il ne part au serveur qu'au
  /// relâchement — pas à chaque pixel parcouru.
  late List<ListeContacts> _ordre = List.of(widget.toutesLesListes);

  List<Sonnerie> _catalogue = const [];
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _chargerCatalogue();
  }

  Future<void> _chargerCatalogue() async {
    try {
      final depot = context.read<RingtonesRepository>();
      final liste = await depot.list();
      if (!mounted) return;
      setState(() => _catalogue = liste);
    } catch (_) {
      // Le catalogue importé est un PLUS : sans lui, les sonneries livrées
      // restent proposées et l'écran fonctionne. Échouer ici bloquerait le
      // réglage des sons pour une raison sans rapport.
    }
  }

  /// Le libellé d'une valeur stockée — nom de fichier livré, ou URL importée.
  String _libelleDe(String? valeur) {
    if (valeur == null || valeur.isEmpty) return tr(context, 'default_value');
    for (final s in sonneriesLivrees) {
      if (s.fichier == valeur) return s.libelle;
    }
    for (final s in _catalogue) {
      if (s.url == valeur) return s.label;
    }
    // Une sonnerie importée sur un AUTRE appareil : la base la porte, ce
    // téléphone n'a pas le fichier. On le dit plutôt que d'afficher une URL.
    return tr(context, 'ringtone_absent_here');
  }

  Future<void> _choisirSon({required bool pourAppel}) async {
    final actuel = pourAppel ? _sonAppel : _sonMessage;
    final choix = await showModalBottomSheet<({String? valeur})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelecteurSon(
        titre: pourAppel
            ? tr(context, 'ringtone_calls')
            : tr(context, 'ringtone_messages'),
        actuel: actuel,
        catalogue: _catalogue,
      ),
    );
    if (choix == null || !mounted) return;
    setState(() {
      if (pourAppel) {
        _sonAppel = choix.valeur;
      } else {
        _sonMessage = choix.valeur;
      }
    });
    await _enregistrerSons();
  }

  Future<void> _enregistrerSons() async {
    final depot = context.read<ContactListsRepository>();
    setState(() => _envoi = true);
    try {
      await depot.modifier(
        widget.liste.id,
        // ⚠️ Le record présent avec `url: null` REMET la valeur par défaut ;
        // le record absent laisse le champ inchangé. Les deux sons partent
        // ensemble pour que l'écran reflète toujours ce qui est en base.
        sonnerie: (url: _sonAppel),
        sonnerieMessage: (url: _sonMessage),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(tr(context, 'save_failed_short'));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _enregistrerOrdre() async {
    final depot = context.read<ContactListsRepository>();
    // Photo de l'ordre affiché AVANT l'appel : si le serveur refuse, c'est à
    // lui qu'on revient, et non à un état intermédiaire.
    final avant = List.of(_ordre);
    setState(() => _envoi = true);
    try {
      final rendu = await depot.reordonner(_ordre.map((l) => l.id).toList());
      if (!mounted) return;
      // On adopte ce que le SERVEUR rend, jamais ce qu'on croit avoir envoyé :
      // les deux divergent dès qu'un second appareil réordonne en même temps.
      setState(() => _ordre = rendu);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ordre = avant);
      showAppSnackBar(tr(context, 'save_failed_short'));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Explique pourquoi une sonnerie importée ne suit pas d'un appareil à l'autre.
  ///
  /// 🔴 LA QUESTION SE POSE VRAIMENT : le fichier audio ne quitte jamais le
  /// téléphone — la base ne garde qu'un nom. Sans cette explication, l'utilisateur
  /// conclut à une panne de synchronisation.
  void _expliquerSynchronisation() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.devices, color: accentOf(context)),
        title: Text(tr(c, 'ringtone_sync_title'), textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Text(tr(c, 'ringtone_sync_body'), style: const TextStyle(height: 1.45)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr(c, 'ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(
        context,
        tr(context, 'ringtones_of', {'nom': widget.liste.name}),
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Text(
                tr(context, 'ringtones_intro'),
                style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: mutedOf(context, Colors.black54)),
              ),
            ),
            _champSon(
              icone: Icons.chat_bubble_outline,
              etiquette: tr(context, 'ringtone_messages'),
              valeur: _libelleDe(_sonMessage),
              onTap: _envoi ? null : () => _choisirSon(pourAppel: false),
            ),
            const SizedBox(height: 10),
            _champSon(
              icone: Icons.phone_in_talk_outlined,
              etiquette: tr(context, 'ringtone_calls'),
              valeur: _libelleDe(_sonAppel),
              onTap: _envoi ? null : () => _choisirSon(pourAppel: true),
            ),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                tr(context, 'priority_order'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                tr(context, 'priority_order_hint'),
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: mutedOf(context, Colors.black54)),
              ),
            ),
            _listeOrdonnable(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'ringtone_account_wide'),
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: mutedOf(context, Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Le bouton d'explication est posé À CÔTÉ du texte qu'il
                  // développe, pas dans la barre du haut : c'est cette phrase-là
                  // qui soulève la question, et nulle part ailleurs.
                  IconButton(
                    onPressed: _expliquerSynchronisation,
                    icon: const Icon(Icons.info_outline),
                    tooltip: tr(context, 'ringtone_sync_title'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _champSon({
    required IconData icone,
    required String etiquette,
    required String valeur,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: surfacesOf(context).surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Icon(icone, color: accentOf(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiquette,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: mutedOf(context, Colors.black54))),
                  const SizedBox(height: 2),
                  // ⚠️ `maxLines: 1` + ellipse : « Sonnerie par défaut de
                  // l'appareil » dépasse la largeur d'un téléphone étroit, et
                  // sans borne le texte passait SOUS le chevron.
                  Text(
                    valeur,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: faintOf(context, Colors.black38)),
          ]),
        ),
      ),
    );
  }

  Widget _listeOrdonnable() {
    return Container(
      decoration: BoxDecoration(
        color: surfacesOf(context).surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        // Elle vit DANS un ListView : sans cela, deux zones défilantes
        // imbriquées se disputeraient le geste vertical, et le glissement d'une
        // ligne ferait défiler la page.
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _ordre.length,
        // ⚠️ `onReorderItem` ET NON `onReorder`, qui est déprécié depuis Flutter
        // 3.41. La différence n'est pas cosmétique : l'ancien rappel donnait
        // l'index de destination AVANT le retrait de l'élément, et tout appelant
        // devait décrémenter lui-même quand on descendait une ligne — un
        // ajustement qu'il était facile d'oublier, et qui faisait alors
        // atterrir la ligne une place trop bas. Celui-ci le fait pour nous.
        onReorderItem: (de, vers) {
          setState(() {
            final l = _ordre.removeAt(de);
            _ordre.insert(vers, l);
          });
          // Au relâchement seulement — pas à chaque pixel parcouru.
          _enregistrerOrdre();
        },
        itemBuilder: (_, i) {
          final l = _ordre[i];
          final estCelleCi = l.id == widget.liste.id;
          return ListTile(
            key: ValueKey(l.id),
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: accentOf(context).withValues(alpha: 0.12),
              child: Text(
                "${i + 1}",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accentOf(context)),
              ),
            ),
            title: Text(
              l.name,
              style: TextStyle(
                fontWeight: estCelleCi ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: Icon(Icons.drag_handle,
                  color: faintOf(context, Colors.black38)),
            ),
          );
        },
      ),
    );
  }
}

/// Le choix d'un son, livré ou importé.
class _SelecteurSon extends StatelessWidget {
  const _SelecteurSon({
    required this.titre,
    required this.actuel,
    required this.catalogue,
  });

  final String titre;
  final String? actuel;
  final List<Sonnerie> catalogue;

  @override
  Widget build(BuildContext context) {
    // `null` en tête : c'est le repli, et le plus souvent choisi.
    final entrees = <({String? valeur, String libelle})>[
      (valeur: null, libelle: tr(context, 'default_value')),
      ...sonneriesLivrees.map((s) => (valeur: s.fichier, libelle: s.libelle)),
      ...catalogue.map((s) => (valeur: s.url, libelle: s.label)),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controleur) => Container(
        decoration: BoxDecoration(
          color: surfacesOf(context).surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: faintOf(context, Colors.black26),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(titre,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controleur,
              itemCount: entrees.length,
              itemBuilder: (_, i) {
                final e = entrees[i];
                final choisi = e.valeur == actuel;
                return ListTile(
                  title: Text(e.libelle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: choisi
                      ? Icon(Icons.check, color: accentOf(context))
                      : null,
                  onTap: () => Navigator.of(context).pop((valeur: e.valeur)),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
