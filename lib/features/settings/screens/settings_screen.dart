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

/// Écran Paramètres complet — profil, biométrie, langue, sécurité, déconnexion.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _loadingBiometric = true;

  @override
  void initState() {
    super.initState();
    _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    final enabled = await BiometricService.isEnabled();
    final supported = await BiometricService.isDeviceSupported();
    final canCheck = await BiometricService.canCheckBiometrics();
    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = supported || canCheck;
        _loadingBiometric = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && !_biometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Biométrie non disponible sur cet appareil")),
      );
      return;
    }

    if (value) {
      // Teste l'authentification avant d'activer
      final ok = await BiometricService.authenticate();
      if (!ok || !mounted) return;
    }

    await BiometricService.setEnabled(value);
    if (mounted) {
      setState(() => _biometricEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? "Biométrie activée"
              : "Biométrie désactivée"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final localeCtrl = context.watch<LocaleController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: backAppBar(context, "Paramètres"),
      body: ListView(
        children: [
          // ================================================================
          // SECTION : PROFIL
          // ================================================================
          _sectionHeader("Profil"),
          // Carte profil
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1B18) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF2A2520)
                    : AlanyaColors.grey200,
                width: 0.5,
              ),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: AvatarCircle(
                name: user?.pseudo ?? "?",
                avatarUrl: user?.avatarUrl,
                radius: 28,
                backgroundColor: AlanyaColors.terracotta,
              ),
              title: Text(user?.pseudo ?? "Utilisateur",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(
                "Numéro Alanya : ${user?.publicNumber ?? '—'}",
                style: TextStyle(
                    fontSize: 13, color: AlanyaColors.grey500),
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ),

          // ================================================================
          // SECTION : SÉCURITÉ
          // ================================================================
          _sectionHeader("Sécurité"),
          _settingsTile(
            icon: Icons.fingerprint,
            iconColor: AlanyaColors.terracotta,
            title: "Verrouillage biométrique",
            subtitle: _loadingBiometric
                ? "Chargement..."
                : (_biometricEnabled
                    ? "Activé — l'app se verrouille avec votre empreinte"
                    : "Désactivé — déverrouiller sans authentification"),
            trailing: _loadingBiometric
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Switch(
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: AlanyaColors.terracotta,
                  ),
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

          // ================================================================
          // SECTION : PRÉFÉRENCES
          // ================================================================
          _sectionHeader("Préférences"),
          _settingsTile(
            icon: Icons.language,
            iconColor: AlanyaColors.forest,
            title: tr(context, 'language'),
            subtitle: _currentLanguageName(localeCtrl),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _showLanguagePicker(localeCtrl),
          ),
          _settingsTile(
            icon: Icons.notifications_outlined,
            iconColor: AlanyaColors.gold,
            title: "Notifications",
            subtitle: "Gérer les notifications push",
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Bientôt disponible")),
              );
            },
          ),
          _settingsTile(
            icon: Icons.privacy_tip_outlined,
            iconColor: AlanyaColors.chocolate,
            title: "Confidentialité",
            subtitle: "Paramètres de confidentialité",
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Bientôt disponible")),
              );
            },
          ),

          // ================================================================
          // SECTION : COMPTE
          // ================================================================
          _sectionHeader("Compte"),
          _settingsTile(
            icon: Icons.info_outline,
            iconColor: AlanyaColors.grey500,
            title: "À propos d'Alanya",
            subtitle: "Version 1.0.0",
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _showAbout(),
          ),
          const SizedBox(height: 12),
          // Bouton déconnexion
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Se déconnecter ?"),
                    content: const Text(
                        "Vous devrez vous reconnecter pour accéder à vos messages."),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Annuler")),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.read<AuthController>().logout();
                        },
                        child: const Text("Déconnexion",
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text("Se déconnecter",
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: Colors.red.shade200),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- Helpers ---

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.grey500,
          letterSpacing: 1.2,
        ),
      ),
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
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
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
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(fontSize: 12, color: AlanyaColors.grey500))
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  String _currentLanguageName(LocaleController localeCtrl) {
    final match = LocaleController.supported
        .where((l) => l.code == localeCtrl.languageCode);
    return match.isNotEmpty ? match.first.nativeName : 'Français';
  }

  void _showLanguagePicker(LocaleController localeCtrl) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AlanyaColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Choisir la langue",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...LocaleController.supported.map((l) {
              final selected = localeCtrl.languageCode == l.code;
              return ListTile(
                leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
                title: Text(l.nativeName,
                    style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
                trailing: selected
                    ? Icon(Icons.check, color: AlanyaColors.terracotta)
                    : null,
                onTap: () {
                  localeCtrl.setLocale(l.code);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AlanyaColors.terracotta, AlanyaColors.terracottaDark],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(Icons.chat_bubble, size: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            const Text("ALANYA",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4)),
            const SizedBox(height: 4),
            Text("Version 1.0.0",
                style: TextStyle(color: AlanyaColors.grey500)),
            const SizedBox(height: 8),
            Text(
              "Application de messagerie instantanée",
              style: TextStyle(color: AlanyaColors.grey500, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              "© 2026 Dominique BRIA",
              style: TextStyle(color: AlanyaColors.grey400, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fermer")),
        ],
      ),
    );
  }
}
