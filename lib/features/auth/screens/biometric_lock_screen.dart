import 'package:flutter/material.dart';
import '../../../core/biometric_service.dart';
import '../../../widgets/alanya_wordmark.dart';
import '../../../theme/alanya_theme.dart';
import '../../../l10n/app_localizations.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen(
      {super.key, required this.onUnlocked, this.onDisabled});
  final VoidCallback onUnlocked;

  /// Le verrou vient d'être désactivé, après le code de l'appareil.
  final VoidCallback? onDisabled;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    // Lance l'auth automatiquement
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);

    final ok = await BiometricService.authenticate();
    if (!mounted) return;
    setState(() => _authenticating = false);

    if (ok) {
      widget.onUnlocked();
    }
  }

  Future<void> _authenticateWithPin() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);

    final ok = await BiometricService.authenticateWithFallback();
    if (!mounted) return;
    setState(() => _authenticating = false);

    if (ok) {
      widget.onUnlocked();
    }
  }

  /// Désactive le verrou — APRÈS le code de l'appareil.
  ///
  /// 🐛 LE BOUTON DÉSACTIVAIT SANS RIEN DEMANDER (relevé le 18/10/2026) : quiconque
  /// tenait le téléphone ouvrait l'application d'un appui, sans empreinte ni
  /// code. Le verrou ne protégeait donc de rien.
  Future<void> _desactiver() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final ok = await BiometricService.authenticateWithFallback();
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (!ok) return;
    await BiometricService.setEnabled(false);
    widget.onDisabled?.call();
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfacesOf(context).fond,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                // L'icône de l'application, celle de l'écran d'accueil du
                // téléphone — pas un « A » dessiné (user, 18/10/2026). Sur sa
                // plaque blanche, comme l'icône elle-même, pour rester lisible
                // en thème sombre.
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 84,
                    height: 84,
                    color: Colors.white,
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const AlanyaWordmark(fontSize: 24, letterSpacing: 3),
                const SizedBox(height: 40),

                // Bouton empreinte
                GestureDetector(
                  onTap: _authenticating ? null : _authenticate,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: accentOf(context).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accentOf(context).withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: _authenticating
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: accentOf(context)),
                          )
                        : Icon(Icons.fingerprint,
                            size: 36, color: accentOf(context)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _authenticating
                      ? tr(context, 'biometric_verifying')
                      : tr(context, 'biometric_tap_unlock'),
                  style: TextStyle(
                      fontSize: 13, color: mutedOf(context, AlanyaColors.grey500)),
                ),
                const SizedBox(height: 32),

                // Fallback : code de l'appareil
                TextButton.icon(
                  onPressed: _authenticating ? null : _authenticateWithPin,
                  icon: Icon(Icons.lock_outline,
                      size: 18, color: mutedOf(context, AlanyaColors.grey500)),
                  label: Text(tr(context, 'use_device_code'),
                      style: TextStyle(color: mutedOf(context, AlanyaColors.grey500))),
                ),
                const SizedBox(height: 8),

                // Désactiver la biométrie
                TextButton(
                  onPressed: _authenticating ? null : _desactiver,
                  child: Text(
                    tr(context, 'disable_lock'),
                    style: TextStyle(
                        fontSize: 12, color: mutedOf(context, AlanyaColors.grey400)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
