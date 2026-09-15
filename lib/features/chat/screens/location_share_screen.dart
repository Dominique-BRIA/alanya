import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../models/message_payload.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/media/location_bubble.dart';
import '../../../widgets/media/osm_static_map.dart';
import '../../../l10n/app_localizations.dart';

/// Aperçu d'une position avant de l'envoyer.
///
/// Remplace la boîte de dialogue où l'utilisateur DEVAIT TAPER ses coordonnées
/// à la main, alors que `geolocator` est dans l'application depuis le chantier
/// de géolocalisation d'entreprise. Personne ne connaît sa latitude.
///
/// ⚠️ La saisie manuelle n'a pas disparu pour autant : elle servait à partager
/// la position d'un LIEU (« venez visiter notre boutique »), qui n'est pas celle
/// du téléphone. Elle est reléguée en action secondaire.
class LocationShareScreen extends StatefulWidget {
  const LocationShareScreen({super.key});

  static Future<SharedLocation?> open(BuildContext context) {
    return Navigator.of(context).push<SharedLocation>(
      MaterialPageRoute(builder: (_) => const LocationShareScreen()),
    );
  }

  @override
  State<LocationShareScreen> createState() => _LocationShareScreenState();
}

class _LocationShareScreenState extends State<LocationShareScreen> {
  Position? _position;
  bool _chargement = true;
  String? _erreur;
  bool _serviceCoupe = false;
  final _libelleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _releve();
  }

  @override
  void dispose() {
    _libelleCtrl.dispose();
    super.dispose();
  }

  Future<void> _releve() async {
    setState(() {
      _chargement = true;
      _erreur = null;
      _serviceCoupe = false;
    });

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _serviceCoupe = true;
        _erreur = tr(context, 'location_disabled_phone');
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _chargement = false;
        _erreur = permission == LocationPermission.deniedForever
            ? tr(context, 'location_denied_forever')
            : tr(context, 'location_denied');
      });
      return;
    }

    try {
      // Plafond de temps : sans lui, un premier point GPS en intérieur peut ne
      // jamais arriver et l'écran resterait à tourner indéfiniment.
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = p;
        _chargement = false;
      });
    } catch (_) {
      // Le point précis n'est pas venu à temps : le DERNIER point connu vaut
      // mieux qu'un échec — c'est souvent le même endroit, à quelques minutes
      // près, et l'utilisateur voit la précision affichée.
      try {
        final dernier = await Geolocator.getLastKnownPosition();
        if (!mounted) return;
        if (dernier != null) {
          setState(() {
            _position = dernier;
            _chargement = false;
          });
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = tr(context, 'position_not_found');
      });
    }
  }

  void _envoyer() {
    final p = _position;
    if (p == null) return;
    final libelle = _libelleCtrl.text.trim();
    Navigator.of(context).pop(SharedLocation(
      lat: p.latitude,
      lng: p.longitude,
      accuracy: p.accuracy,
      label: libelle.isEmpty ? null : libelle,
    ));
  }

  /// Partage d'un LIEU dont on connaît les coordonnées, et non de soi-même.
  Future<void> _saisieManuelle() async {
    final ctrlLat = TextEditingController();
    final ctrlLng = TextEditingController();
    final ctrlNom = TextEditingController();
    final valide = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr(ctx, 'enter_coordinates')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            tr(ctx, 'coordinates_explain'),
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrlLat,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
                labelText: tr(ctx, 'latitude'), hintText: "3.8480", isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrlLng,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
                labelText: tr(ctx, 'longitude'), hintText: "11.5020", isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrlNom,
            decoration: InputDecoration(
                labelText: tr(ctx, 'place_name_optional'), isDense: true),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, 'validate'))),
        ],
      ),
    );
    if (valide != true || !mounted) return;

    // Les bornes sont celles du serveur : mieux vaut refuser ici, avec une
    // phrase, que d'envoyer une charge que l'API rejettera.
    final lat = double.tryParse(ctrlLat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(ctrlLng.text.trim().replaceAll(',', '.'));
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'coordinates_invalid'))));
      return;
    }
    final nom = ctrlNom.text.trim();
    if (!mounted) return;
    Navigator.of(context).pop(SharedLocation(
      lat: lat,
      lng: lng,
      label: nom.isEmpty ? null : nom,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _position;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'share_location')),
        actions: [
          IconButton(
            tooltip: tr(context, 'enter_coordinates'),
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: _saisieManuelle,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _chargement
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: accentOf(context)),
                        const SizedBox(height: 12),
                        Text(tr(context, 'locating')),
                      ],
                    ),
                  )
                : p == null
                    ? _echec()
                    : LayoutBuilder(
                        builder: (ctx, contraintes) => Stack(children: [
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () =>
                                  ouvrirCarteExterne(p.latitude, p.longitude),
                              child: OsmStaticMap(
                                lat: p.latitude,
                                lng: p.longitude,
                                width: contraintes.maxWidth,
                                height: contraintes.maxHeight,
                                zoom: 16,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tr(context, 'location_accuracy', {
                                  'precision': '${p.accuracy.round()}',
                                  'lat': p.latitude.toStringAsFixed(5),
                                  'lng': p.longitude.toStringAsFixed(5),
                                }),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ]),
                      ),
          ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _libelleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: tr(context, 'accuracy_note_optional'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _envoyer,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: accentOf(context), shape: BoxShape.circle),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 22),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _echec() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.location_off_outlined,
              size: 52, color: AlanyaColors.grey400),
          const SizedBox(height: 12),
          Text(_erreur ?? tr(context, 'position_unavailable'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            if (_serviceCoupe)
              OutlinedButton.icon(
                onPressed: () => Geolocator.openLocationSettings(),
                icon: const Icon(Icons.settings, size: 16),
                label: Text(tr(context, 'enable_location')),
              ),
            OutlinedButton.icon(
              onPressed: _releve,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr(context, 'retry')),
            ),
            TextButton.icon(
              onPressed: _saisieManuelle,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
              label: Text(tr(context, 'enter_coordinates')),
            ),
          ]),
        ]),
      ),
    );
  }
}
