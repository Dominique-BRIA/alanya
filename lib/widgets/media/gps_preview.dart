import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/alanya_theme.dart';

class GpsCoords {
  final double lat;
  final double lng;
  const GpsCoords({required this.lat, required this.lng});
}

GpsCoords? extractGpsCoords(String text) {
  final gmaps = RegExp(r'(?:google\.\w+/maps|maps\.google\.\w+|goo\.gl/maps).*?[/@](-?\d+\.\d+),(-?\d+\.\d+)');
  final gm = gmaps.firstMatch(text);
  if (gm != null) {
    return GpsCoords(lat: double.parse(gm.group(1)!), lng: double.parse(gm.group(2)!));
  }
  final gpsRegex = RegExp(r'(-?\d+\.\d{2,})\s*,\s*(-?\d+\.\d{2,})');
  final match = gpsRegex.firstMatch(text);
  if (match != null) {
    return GpsCoords(lat: double.parse(match.group(1)!), lng: double.parse(match.group(2)!));
  }
  return null;
}

class GpsPreview extends StatelessWidget {
  final double lat;
  final double lng;
  final bool isMe;

  const GpsPreview({
    super.key,
    required this.lat,
    required this.lng,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final osmUrl = "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=15/$lat/$lng";
    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () async {
          final uri = Uri.parse(osmUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isMe ? Colors.white.withValues(alpha: 0.1) : const Color(0xFF1E293B),
            border: Border.all(
              color: isMe ? Colors.white.withValues(alpha: 0.2) : AlanyaColors.grey200,
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Localisation GPS",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white : Colors.white,
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_new, size: 14, color: isMe ? Colors.white70 : Colors.white60),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF0F172A),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.4,
                          child: Container(
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_pin, color: Color(0xFFEF4444), size: 36),
                          const SizedBox(height: 2),
                          Text(
                            "Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Ouvrir dans OpenStreetMap / Maps",
                style: TextStyle(
                  fontSize: 11,
                  color: isMe ? AlanyaColors.gold : const Color(0xFF38BDF8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
