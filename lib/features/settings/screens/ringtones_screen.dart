import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../core/ringtone_service.dart';
import '../../../core/token_storage.dart';
import '../../../core/texte_recherche.dart';
import '../../../models/sonnerie.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../../../widgets/motif_background.dart';
import '../ringtones_repository.dart';

/// Catalogue de sonneries importées.
///
/// L'import se fait en deux temps — téléversement puis inscription — mais
/// l'utilisateur ne voit qu'un geste : choisir un fichier.
class RingtonesScreen extends StatefulWidget {
  const RingtonesScreen({super.key});

  @override
  State<RingtonesScreen> createState() => _RingtonesScreenState();
}

class _RingtonesScreenState extends State<RingtonesScreen> {
  List<Sonnerie>? _sonneries;
  bool _chargement = false;
  String? _erreur;

  /// Progression de l'import en cours, entre 0 et 1. Nulle hors import.
  double? _progression;

  /// L'URL en cours d'écoute, pour montrer quel élément joue.
  String? _enEcoute;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    // Une écoute laissée en cours continuerait après la fermeture de l'écran.
    RingtoneService.instance.stopIvr();
    super.dispose();
  }

  Future<void> _charger() async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final depot = context.read<RingtonesRepository>();
    try {
      final l = await depot.list();
      if (!mounted) return;
      setState(() {
        _sonneries = l;
        _chargement = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Erreur ${e.statusCode} : ${e.message}";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = "Impossible de charger vos sonneries.";
      });
    }
  }

  Future<void> _importer() async {
    final depot = context.read<RingtonesRepository>();

    // `withData: true` : on a besoin des OCTETS, pas d'un chemin. Sur Android,
    // un fichier choisi hors du bac à sable de l'application n'est pas lisible
    // par son chemin — c'est le sélecteur qui doit les fournir.
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (choix == null || choix.files.isEmpty) return;
    final f = choix.files.first;
    final octets = f.bytes;
    if (octets == null) {
      showAppSnackBar("Fichier illisible");
      return;
    }

    // ⚠️ Un plafond ANNONCÉ vaut mieux qu'un 413 après une minute d'envoi sur un
    // réseau lent. 10 Mo laisse largement la place à une sonnerie ; au-delà,
    // c'est un morceau entier, pas une sonnerie.
    const plafondOctets = 10 * 1024 * 1024;
    if (octets.length > plafondOctets) {
      showAppSnackBar("Fichier trop lourd (10 Mo maximum)");
      return;
    }

    setState(() => _progression = 0);
    try {
      await depot.importer(
        octets: octets,
        nomFichier: f.name,
        // Le sélecteur ne rend pas toujours un type MIME : on retombe sur un
        // type audio générique plutôt que d'échouer, le serveur ne relit pas le
        // fichier de toute façon.
        typeMime: _typeMimeDe(f.extension),
        // Le nom du fichier SANS son extension : « ma-sonnerie.mp3 » se lit mal
        // dans une liste de choix. Le serveur coupe à 80 caractères de son côté.
        libelle: _libelleDepuis(f.name),
        onProgress: (envoyes, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progression = envoyes / total);
        },
      );
      if (!mounted) return;
      setState(() => _progression = null);
      await _charger();
      showAppSnackBar("Sonnerie ajoutée");
    } on ApiException catch (e) {
      if (mounted) setState(() => _progression = null);
      showAppSnackBar(e.message);
    } catch (_) {
      if (mounted) setState(() => _progression = null);
      showAppSnackBar("Import impossible");
    }
  }

  static String _libelleDepuis(String nomFichier) {
    final point = nomFichier.lastIndexOf('.');
    final sansExtension =
        point > 0 ? nomFichier.substring(0, point) : nomFichier;
    final propre = sansExtension.trim();
    return propre.isEmpty ? "Sonnerie" : propre;
  }

  static String _typeMimeDe(String? extension) {
    switch ((extension ?? "").toLowerCase()) {
      case "mp3":
        return "audio/mpeg";
      case "wav":
        return "audio/wav";
      case "ogg":
        return "audio/ogg";
      case "m4a":
      case "aac":
        return "audio/aac";
      default:
        return "audio/mpeg";
    }
  }

  Future<void> _ecouter(Sonnerie s) async {
    if (_enEcoute == s.url) {
      await RingtoneService.instance.stopIvr();
      if (mounted) setState(() => _enEcoute = null);
      return;
    }

    /*
     * ⚠️ L'URL DU CATALOGUE EST RELATIVE — `/api/media/<id>` — et la route des
     * médias exige un JETON. Le lecteur audio ne sait pas joindre d'en-tête
     * `Authorization` : le jeton passe donc en paramètre, comme partout ailleurs
     * dans l'application (voir la citation d'un message dans la discussion).
     *
     * La donner telle quelle au lecteur donnerait un silence sans erreur — le
     * pire des échecs, et exactement celui qu'on vient de corriger sur l'IVR.
     */
    final base = context.read<ApiClient>().baseUrl;
    final jeton = await context.read<TokenStorage>().accessToken;
    if (!mounted) return;

    setState(() => _enEcoute = s.url);
    // Une seule écoute à la fois : `playIvrPrompt` coupe la précédente.
    await RingtoneService.instance
        .playIvrPrompt("$base${s.url}?token=$jeton", loop: false);
  }

  Future<void> _supprimer(Sonnerie s) async {
    final depot = context.read<RingtonesRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Retirer cette sonnerie ?"),
        content: Text(
          "« ${s.label} » sortira de votre catalogue.\n\n"
          "Les listes qui l'utilisaient reviendront à la sonnerie par défaut.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Retirer")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await depot.supprimer(s.id);
      await _charger();
    } catch (_) {
      showAppSnackBar("Suppression impossible");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, "Mes sonneries"),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _progression != null ? null : _importer,
        icon: const Icon(Icons.library_music_outlined),
        label: Text(_progression == null ? "Importer" : "Envoi…"),
      ),
      body: MotifBackground(
        overlayOpacity: 0.92,
        child: Column(children: [
          if (_progression != null)
            LinearProgressIndicator(
              value: _progression,
              color: accentOf(context),
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _charger, child: _corps()),
          ),
        ]),
      ),
    );
  }

  Widget _corps() {
    if (_sonneries == null && _chargement) {
      return Center(child: CircularProgressIndicator(color: accentOf(context)));
    }
    if (_erreur != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _charger, child: const Text("Réessayer")),
            ]),
          ),
        ),
      ]);
    }

    final sonneries = List<Sonnerie>.from(_sonneries ?? const <Sonnerie>[])
      ..sort((a, b) => comparePourTri(a.label, b.label));

    if (sonneries.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              Icon(Icons.music_note_outlined,
                  size: 56, color: faintOf(context, Colors.black26)),
              const SizedBox(height: 16),
              const Text("Aucune sonnerie importée",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                "Importez un fichier audio pour l'attribuer ensuite à une "
                "liste de contacts.",
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedOf(context, Colors.black54)),
              ),
            ]),
          ),
        ),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: sonneries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = sonneries[i];
        final joue = _enEcoute == s.url;
        return ListTile(
          leading: IconButton(
            icon: Icon(
                joue ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            color: accentOf(context),
            iconSize: 34,
            onPressed: () => _ecouter(s),
            tooltip: joue ? "Arrêter" : "Écouter",
          ),
          title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _supprimer(s),
            tooltip: "Retirer",
          ),
        );
      },
    );
  }
}
