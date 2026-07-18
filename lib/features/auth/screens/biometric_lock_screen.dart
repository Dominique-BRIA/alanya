import 'package:flutter/material.dart';

import '../../../core/biometric_service.dart';
import '../../../theme/alanya_theme.dart';

/// Écran de verrouillage biométrique — affiché au lancement de l'app
/// si l'utilisateur a activé la biométrie.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Lance automatiquement l'authentification biométrique au chargement.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });

    final ok = await BiometricService.authenticate();

    if (!mounted) return;
    setState(() => _authenticating = false);

    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = "Authentification échouée. Réessaie.");
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
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AlanyaColors.terracotta, AlanyaColors.terracottaDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AlanyaColors.terracotta.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.lock_outline, size: 44, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "ALANYA",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AlanyaColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Déverrouille pour continuer",
                  style: TextStyle(
                    fontSize: 14,
                    color: AlanyaColors.grey500,
                  ),
                ),
                const SizedBox(height: 40),

                // Bouton biométrie
                GestureDetector(
                  onTap: _authenticating ? null : _authenticate,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _authenticating
                          ? AlanyaColors.terracotta.withValues(alpha: 0.1)
                          : AlanyaColors.terracotta.withValues(alpha: 0.08),
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
                              color: AlanyaColors.terracotta,
                            ),
                          )
                        : const Icon(
                            Icons.fingerprint,
                            size: 38,
                            color: AlanyaColors.terracotta,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _authenticating ? null : _authenticate,
                  child: Text(
                    "Réessayer",
                    style: TextStyle(color: AlanyaColors.grey500),
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
