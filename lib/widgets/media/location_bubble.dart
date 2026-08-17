import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/message_payload.dart';
import '../../theme/alanya_theme.dart';
import 'osm_static_map.dart';

/// Ouvre une position dans l'application de cartes du téléphone.
///
/// L'URI `geo:` est essayée d'abord : c'est celle que TOUTES les applications de
/// cartes d'Android déclarent, donc l'utilisateur retrouve celle qu'il utilise
/// déjà (Google Maps, Waze, OsmAnd…) au lieu de se voir imposer un site.
/// Le repli web sert au cas où aucune n'est installée — et sur un téléphone qui
/// n'a aucune application de cartes, le navigateur reste une réponse.
Future<bool> ouvrirCarteExterne(double lat, double lng, {String? label}) async {
  final etiquette = (label != null && label.trim().isNotEmpty)
      ? Uri.encodeComponent(label.trim())
      : null;
  final geo = Uri.parse(
      "geo:$lat,$lng?q=$lat,$lng${etiquette != null ? "($etiquette)" : ""}");
  try {
    if (await canLaunchUrl(geo)) {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }
  } catch (_) {
    // Un `geo:` refusé n'est pas un échec : le repli web suit.
  }
  final web = Uri.parse(
      "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng");
  try {
    return await launchUrl(web, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Bulle « position partagée » — carte réelle, libellé, précision.
///
/// Toucher la carte ouvre l'application de cartes du téléphone : une vignette
/// ne sert qu'à reconnaître le lieu, l'itinéraire est le travail d'une vraie
/// application de cartes.
class LocationBubble extends StatelessWidget {
  const LocationBubble({
    super.key,
    required this.position,
    this.onLongPress,
    this.timestamp,
    this.statusWidget,
    this.isMe = false,
  });

  final SharedLocation position;
  final VoidCallback? onLongPress;
  final String? timestamp;
  final Widget? statusWidget;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final surfaces = surfacesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onText = isMe ? surfaces.texteBulleEnvoyee : surfaces.texteBulleRecue;
    final onSub =
        isMe ? Colors.white70 : (dark ? AlanyaColors.craie2 : Colors.black54);

    final precision = position.accuracy;
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: () =>
          ouvrirCarteExterne(position.lat, position.lng, label: position.label),
      child: SizedBox(
        width: 236,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            OsmStaticMap(
                lat: position.lat, lng: position.lng, width: 236, height: 132),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.location_on,
                  size: 16,
                  color: isMe ? Colors.white : const Color(0xFFEF4444)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  position.label ?? "Position partagée",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: onText),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
              // La précision est affichée parce qu'elle change le sens de ce
              // qu'on reçoit : une position à 1 200 m près ne désigne pas un
              // lieu, elle désigne un quartier.
              precision != null
                  ? "Précision ${precision.round()} m · ${_coord(position)}"
                  : _coord(position),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: onSub),
            ),
            if (timestamp != null) ...[
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Spacer(),
                Text(timestamp!, style: TextStyle(fontSize: 11, color: onSub)),
                if (statusWidget != null) ...[
                  const SizedBox(width: 3),
                  statusWidget!,
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }

  static String _coord(SharedLocation p) =>
      "${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}";
}
