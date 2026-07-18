import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/biometric_service.dart';
import '../../../core/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../../account/screens/profile_screen.dart';
import '../../blocked/screens/blocked_users_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _biometricType = "Chargement...";
  bool _loadingBiometric = true;

  @override
  void initState() {
    super.initState();
    _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    try {
      final enabled = await BiometricService.isEnabled();
      final available = await BiometricService.isAvailable();
      final desc = await BiometricService.getBiometricDescription();
      if (mounted) {
        setState(() {
          _biometricEnabled = enabled;
          _biometricAvailable = available;
          _biometricType = desc;
          _loadingBiometric = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _biometricEnabled = false;
          _biometricAvailable = false;
          _biometricType = "Erreur";
          _loadingBiometric = false;
        });
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      if (!_biometricAvailable) {
        _snack("Biométrie non disponible. Configurez l'empreinte ou le visage dans les paramètres de votre appareil.");
        return;
      }
      final ok = await BiometricService.authenticate(
        reason: 'Activer le verrouillage biométrique',
      );
      if (!ok || !mounted) {
        if (mounted) _snack("Authentification annulée");
        return;
      }
      await BiometricService.setEnabled(true);
      setState(() => _biometricEnabled = true);
      _snack("Verrouillage biométrique activé ($_biometricType)");
    } else {
      await BiometricService.setEnabled(false);
      setState(() => _biometricEnabled = false);
      _snack("Verrouillage biométrique désactivé");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final localeCtrl = context.watch<LocaleController>();

    return Scaffold(
      appBar: backAppBar(context, "Paramètres"),
      body: ListView(
        children: [
          // PROFIL
          _sectionHeader("Profil"),
          _card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: AvatarCircle(
                name: user?.pseudo ?? "?",
                avatarUrl: user?.avatarUrl,
                radius: 28,
                backgroundColor: AlanyaColors.terracotta,
              ),
              title: Text(user?.pseudo ?? "Utilisateur",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text("Numéro Alanya : ${user?.publicNumber ?? '—'}",
                  style: TextStyle(fontSize: 13, color: AlanyaColors.grey500)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ),

          // SECURITE
          _sectionHeader("Sécurité"),
          _settingsTile(
            icon: _biometricEnabled ? Icons.fingerprint : Icons.fingerprint_outlined,
            iconColor: _biometricEnabled ? AlanyaColors.forest : AlanyaColors.grey400,
            title: "Verrouillage biométrique",
            subtitle: _loadingBiometric
                ? "Chargement..."
                : (!_biometricAvailable
                    ? "Non disponible sur cet appareil"
                    : (_biometricEnabled
                        ? "Activé — $_biometricType (appuyer pour désactiver)"
                        : "Désactivé (appuyer pour activer)")),
            trailing: _loadingBiometric
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _biometricEnabled
                          ? AlanyaColors.forest.withValues(alpha: 0.1)
                          : AlanyaColors.grey200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _biometricEnabled ? "ON" : "OFF",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _biometricEnabled ? AlanyaColors.forest : AlanyaColors.grey500,
                      ),
                    ),
                  ),
            onTap: _loadingBiometric ? null : () => _toggleBiometric(!_biometricEnabled),
          ),
          _settingsTile(
            icon: Icons.block,
            iconColor: Colors.red.shade400,
            title: "Utilisateurs bloqués",
            subtitle: "Gérer les personnes bloquées",
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),

          // PREFERENCES
          _sectionHeader("Préférences"),
          _settingsTile(
            icon: Icons.language,
            iconColor: AlanyaColors.forest,
            title: tr(context, 'language'),
            subtitle: _currentLanguageName(localeCtrl),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: LocaleController.supported.any((l) => l.code == localeCtrl.languageCode)
                    ? localeCtrl.languageCode
                    : 'fr',
                icon: Icon(Icons.expand_more, color: AlanyaColors.grey400, size: 20),
                items: LocaleController.supported.map((l) {
                  return DropdownMenuItem(
                    value: l.code,
                    child: Text('${l.flag}  ${l.nativeName}', style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (code) {
                  if (code != null) localeCtrl.setLocale(code);
                },
              ),
            ),
          ),

          // COMPTE
          _sectionHeader("Compte"),
          _settingsTile(
            icon: Icons.info_outline,
            iconColor: AlanyaColors.grey500,
            title: "À propos d'Alanya",
            subtitle: "Version 1.0.0",
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _showAbout(),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Se déconnecter ?"),
                    content: const Text("Vous devrez vous reconnecter pour accéder à vos messages."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.read<AuthController>().logout();
                        },
                        child: const Text("Déconnexion", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text("Se déconnecter", style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: Colors.red.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AlanyaColors.grey500, letterSpacing: 1.2)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AlanyaColors.grey200, width: 0.5),
      ),
      child: child,
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: AlanyaColors.grey500))
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  String _currentLanguageName(LocaleController localeCtrl) {
    final match = LocaleController.supported.where((l) => l.code == localeCtrl.languageCode);
    return match.isNotEmpty ? match.first.nativeName : 'Français';
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              "assets/images/app_icon.png",
              width: 72,
              height: 72,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AlanyaColors.terracotta, AlanyaColors.terracottaDark]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Icon(Icons.chat_bubble, size: 36, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            const Text("ALANYA", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4)),
            const SizedBox(height: 4),
            Text("Version 1.0.0", style: TextStyle(color: AlanyaColors.grey500)),
            const SizedBox(height: 8),
            Text("Application de messagerie instantanée", style: TextStyle(color: AlanyaColors.grey500, fontSize: 13)),
            const SizedBox(height: 16),
            Text("© 2026 Dominique BRIA", style: TextStyle(color: AlanyaColors.grey400, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer")),
        ],
      ),
    );
  }
}
