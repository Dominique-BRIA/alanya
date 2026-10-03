import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/lien_alanya.dart';
import '../../../l10n/app_localizations.dart';

/// LE LECTEUR DE QR CODE ALANYA.
///
/// Il ne fait QUE lire : il rend la [CibleLien] reconnue à l'écran qui l'a
/// ouvert (`Navigator.pop`), et c'est celui-ci qui décide quoi en faire. Le
/// même lecteur pourra ainsi servir ailleurs (vérification des clés de
/// chiffrement, dont le bouton « Scanner son code » attend toujours).
///
/// Deux sources :
///   · la caméra ;
///   · une IMAGE de la galerie — le cas d'un QR reçu par WhatsApp ou Facebook
///     sur le téléphone même qui doit le lire : on ne peut pas se filmer
///     soi-même.
///
/// Un code étranger (site web, wifi…) ne ferme pas l'écran : on le signale et
/// la lecture continue.
///
/// ⚠️ Fond NOIR dans tous les thèmes, comme toute vue caméra : le cadre et les
/// textes sont donc blancs, sans branche Nuit.
class ScannerQrScreen extends StatefulWidget {
  const ScannerQrScreen({super.key});

  @override
  State<ScannerQrScreen> createState() => _ScannerQrScreenState();
}

class _ScannerQrScreenState extends State<ScannerQrScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // `noDuplicates` : un même code n'est remonté qu'une fois, sans quoi le
    // message « pas un code Alanya » repartirait à chaque image.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Vrai dès qu'un code valide est retenu : les détections suivantes, déjà
  /// en route, ne doivent pas refermer l'écran une seconde fois.
  bool _termine = false;
  String? _message;
  Timer? _effaceMessage;

  @override
  void dispose() {
    _effaceMessage?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dire(String message) {
    _effaceMessage?.cancel();
    setState(() => _message = message);
    _effaceMessage = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _message = null);
    });
  }

  /// Retient le premier code Alanya d'une capture. Renvoie vrai si un code
  /// (même étranger) y figurait.
  bool _traiter(BarcodeCapture capture) {
    if (_termine) return true;
    var vuUnCode = false;
    for (final code in capture.barcodes) {
      final brut = code.rawValue;
      if (brut == null) continue;
      vuUnCode = true;
      final cible = analyserLienAlanya(brut);
      if (cible != null) {
        _termine = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(cible);
        return true;
      }
    }
    if (vuUnCode) _dire(tr(context, 'qr_scan_not_alanya'));
    return vuUnCode;
  }

  Future<void> _depuisGalerie() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    try {
      final capture = await _controller.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted) return;
      if (capture == null || !_traiter(capture)) {
        _dire(tr(context, 'qr_scan_no_code'));
      }
    } catch (_) {
      if (mounted) _dire(tr(context, 'qr_scan_no_code'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cote = MediaQuery.sizeOf(context).shortestSide * 0.68;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(tr(context, 'qr_scan_title')),
        actions: [
          IconButton(
            tooltip: tr(context, 'qr_scan_torch'),
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _traiter,
            errorBuilder: (context, erreur) => _erreurCamera(erreur),
          ),
          // Le cadre de visée : décoratif, la lecture couvre toute l'image.
          Center(
            child: Container(
              width: cote,
              height: cote,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _message ?? tr(context, 'qr_scan_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _depuisGalerie,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(tr(context, 'qr_scan_gallery')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Caméra refusée ou indisponible : la galerie, elle, reste utilisable.
  Widget _erreurCamera(MobileScannerException erreur) {
    final refus = erreur.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                refus
                    ? tr(context, 'qr_scan_camera_denied')
                    : tr(context, 'qr_scan_camera_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
