import 'package:flutter/material.dart';

import '../core/biometric_service.dart';
import '../features/auth/screens/biometric_lock_screen.dart';

/// Widget qui vérifie si la biométrie est activée au lancement.
/// Si oui, affiche l'écran de verrouillage avant de laisser accéder à l'app.
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool _checking = true;
  bool _needsAuth = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await BiometricService.isEnabled();
    if (!mounted) return;

    if (!enabled) {
      setState(() {
        _checking = false;
        _needsAuth = false;
      });
      return;
    }

    final supported = await BiometricService.isDeviceSupported();
    final canCheck = await BiometricService.canCheckBiometrics();

    if (!mounted) return;
    setState(() {
      _checking = false;
      _needsAuth = enabled && (supported || canCheck);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      // Écran de chargement pendant la vérification
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_needsAuth) {
      return BiometricLockScreen(
        onUnlocked: () {
          if (mounted) setState(() => _needsAuth = false);
        },
      );
    }

    return widget.child;
  }
}
