import 'package:flutter/material.dart';
import '../../../core/biometric_service.dart';
import '../../../theme/alanya_theme.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlanyaColors.cream,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AlanyaColors.terracotta, AlanyaColors.terracottaDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text("A",
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("ALANYA",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6)),
                const SizedBox(height: 40),

                // Bouton empreinte
                GestureDetector(
                  onTap: _authenticating ? null : _authenticate,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AlanyaColors.terracotta.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AlanyaColors.terracotta.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: _authenticating
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AlanyaColors.terracotta),
                          )
                        : const Icon(Icons.fingerprint,
                            size: 36, color: AlanyaColors.terracotta),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _authenticating
                      ? "Vérification..."
                      : "Appuyez pour déverrouiller",
                  style: TextStyle(
                      fontSize: 13, color: AlanyaColors.grey500),
                ),
                const SizedBox(height: 32),

                // Fallback : code de l'appareil
                TextButton.icon(
                  onPressed: _authenticating ? null : _authenticateWithPin,
                  icon: Icon(Icons.lock_outline,
                      size: 18, color: AlanyaColors.grey500),
                  label: Text("Utiliser le code de l'appareil",
                      style: TextStyle(color: AlanyaColors.grey500)),
                ),
                const SizedBox(height: 8),

                // Désactiver la biométrie
                TextButton(
                  onPressed: _authenticating
                      ? null
                      : () async {
                          await BiometricService.setEnabled(false);
                          widget.onUnlocked();
                        },
                  child: Text(
                    "Désactiver le verrouillage",
                    style: TextStyle(
                        fontSize: 12, color: AlanyaColors.grey400),
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
