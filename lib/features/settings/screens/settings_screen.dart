import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/alanya_id_formatter.dart';
import '../../../core/biometric_service.dart';
import '../../../core/data_saver_service.dart';
import '../../../core/locale_controller.dart';
import '../../../core/theme_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/alanya_wordmark.dart';
import '../../../widgets/avatar_circle.dart';
import '../../../widgets/back_app_bar.dart';
import '../../auth/auth_controller.dart';
import '../../account/screens/change_password_screen.dart';
import '../../account/screens/delete_account_screen.dart';
import '../../account/screens/profile_screen.dart';
import 'notification_settings_screen.dart';
import 'ringtones_screen.dart';
import 'translation_screen.dart';
import 'privacy_settings_screen.dart';
import 'login_history_screen.dart';
import 'pays_mobile_screen.dart';
import 'recuperation_screen.dart';
import '../../blocked/screens/blocked_users_screen.dart';
import '../../chat/screens/starred_messages_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  bool _dataSaverEnabled = DataSaverService.instance.isOn;
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
          _biometricType = tr(context, 'error');
          _loadingBiometric = false;
        });
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      if (!_biometricAvailable) {
        _snack(tr(context, 'set_biometric_unavailable'));
        return;
      }
      // Active directement sans vérifier (comme WhatsApp)
      await BiometricService.setEnabled(true);
      // ⚠️ `tr()` LIT LE CONTEXTE, ce qu'un libellé en dur ne faisait pas :
      // après un `await`, l'écran a pu être quitté, et lire le contexte d'un
      // widget démonté lève. La garde protège aussi le `setState` qui suit,
      // lequel n'en avait aucune.
      if (!mounted) return;
      setState(() => _biometricEnabled = true);
      _snack(tr(context, 'set_biometric_on'));
    } else {
      await BiometricService.setEnabled(false);
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      _snack(tr(context, 'set_biometric_off'));
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final localeCtrl = context.watch<LocaleController>();
    final themeCtrl = context.watch<ThemeController>();

    return Scaffold(
      appBar: backAppBar(context, tr(context, 'settings')),
      body: ListView(
        children: [
          // PROFIL
          _sectionHeader(tr(context, 'set_section_profile')),
          _card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: AvatarCircle(
                name: user?.pseudo ?? "?",
                avatarUrl: user?.avatarUrl,
                radius: 28,
                backgroundColor: AlanyaColors.terracotta,
              ),
              title: Text(user?.pseudo ?? tr(context, 'set_user_fallback'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              // Le repli « — » reste hors du formateur : celui-ci ne garde que
              // les chiffres et effacerait le tiret.
              subtitle: Text(
                  tr(context, 'home_alanya_id', {
                    'id': user == null
                        ? '—'
                        : formatAlanyaId(user.publicNumber)
                  }),
                  style: TextStyle(
                      fontSize: 13,
                      // Clair inchangé : `_muted` vaut grey500 en clair.
                      color: alanyaIdOf(context, AlanyaColors.grey500))),
              trailing: _chevron(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ),

          // SECURITE
          _sectionHeader(tr(context, 'set_section_security')),
          _settingsTile(
            icon: Icons.shield_outlined,
            iconColor: _positive,
            title: tr(context, 'set_privacy'),
            subtitle: tr(context, 'set_privacy_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          _settingsTile(
            icon: Icons.history,
            iconColor: _positive,
            title: tr(context, 'set_login_history'),
            subtitle: tr(context, 'set_login_history_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginHistoryScreen()),
            ),
          ),
          _settingsTile(
            icon: Icons.lock_outline,
            iconColor: _accent,
            title: tr(context, 'set_change_password'),
            subtitle: tr(context, 'set_change_password_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          // Pays et telephone. Place dans SECURITE : le numero se change sous
          // mot de passe, et le pays conditionne l indicatif applique au numero.
          _settingsTile(
            icon: Icons.public_outlined,
            iconColor: _accent,
            title: tr(context, 'settings_country_phone'),
            subtitle: tr(context, 'settings_country_phone_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaysMobileScreen()),
            ),
          ),
          // Récupération du compte : revoir son code, ou ajouter une adresse.
          //
          // ⚠️ Montré à TOUS les comptes, y compris ceux qui ont une adresse et
          // donc pas de code : l'écran le dit lui-même. Le masquer aurait
          // demandé de connaître l'état du compte AVANT d'ouvrir les réglages,
          // et une entrée qui apparaît ou non selon le compte est plus
          // déroutante qu'un écran qui explique.
          _settingsTile(
            icon: Icons.key_outlined,
            iconColor: _accent,
            title: tr(context, 'security_recovery_id'),
            subtitle: tr(context, 'security_recovery_id_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecuperationScreen()),
            ),
          ),
          _settingsTile(
            icon: _biometricEnabled
                ? Icons.fingerprint
                : Icons.fingerprint_outlined,
            iconColor: _biometricEnabled ? _positive : _mutedIcon,
            title: tr(context, 'set_biometric_lock'),
            subtitle: _loadingBiometric
                ? tr(context, 'loading')
                : (!_biometricAvailable
                    ? tr(context, 'set_unavailable_here')
                    : (_biometricEnabled
                        ? tr(context, 'set_enabled_tap_off', {'type': _biometricType})
                        : tr(context, 'set_disabled_tap_on'))),
            trailing: _loadingBiometric
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _biometricEnabled
                          ? _positive.withValues(alpha: 0.1)
                          : _chipOffBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _biometricEnabled ? "ON" : "OFF",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _biometricEnabled ? _positive : _muted,
                      ),
                    ),
                  ),
            onTap: _loadingBiometric
                ? null
                : () => _toggleBiometric(!_biometricEnabled),
          ),
          _settingsTile(
            icon: Icons.star,
            iconColor: AlanyaColors.gold,
            title: tr(context, 'set_starred'),
            subtitle: tr(context, 'set_starred_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StarredMessagesScreen()),
            ),
          ),
          _settingsTile(
            icon: Icons.block,
            iconColor: themed(context,
                light: Colors.red.shade400, dark: AlanyaColors.erreurNuit),
            title: tr(context, 'set_blocked'),
            subtitle: tr(context, 'set_blocked_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),

          // PREFERENCES
          _sectionHeader(tr(context, 'set_section_preferences')),
          _settingsTile(
            icon: Icons.notifications_outlined,
            iconColor: _accent,
            title: tr(context, 'set_notifications'),
            subtitle: tr(context, 'set_notifications_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          _settingsTile(
            icon: Icons.library_music_outlined,
            iconColor: _accent,
            title: tr(context, 'set_ringtones'),
            subtitle: tr(context, 'set_ringtones_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RingtonesScreen()),
            ),
          ),
          _settingsTile(
            icon: Icons.translate,
            iconColor: _accent,
            title: tr(context, 'translated'),
            subtitle: tr(context, 'set_translation_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TranslationScreen()),
            ),
          ),
          _settingsTile(
            icon: ThemeController.icone(themeCtrl.choix),
            iconColor: _accent,
            title: tr(context, 'set_theme'),
            subtitle: ThemeController.label(themeCtrl.choix),
            trailing: _chevron(),
            onTap: () => _showThemePicker(themeCtrl),
          ),
          _settingsTile(
            icon:
                _dataSaverEnabled ? Icons.data_saver_on : Icons.data_saver_off,
            iconColor: _dataSaverEnabled ? _positive : _mutedIcon,
            title: tr(context, 'set_data_saver'),
            subtitle: _dataSaverEnabled
                ? tr(context, 'set_data_saver_on')
                : tr(context, 'set_disabled_tap_on'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _dataSaverEnabled
                    ? _positive.withValues(alpha: 0.1)
                    : _chipOffBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _dataSaverEnabled ? "ON" : "OFF",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _dataSaverEnabled ? _positive : _muted,
                ),
              ),
            ),
            onTap: () async {
              final v = !_dataSaverEnabled;
              await DataSaverService.instance.setEnabled(v);
              if (mounted) setState(() => _dataSaverEnabled = v);
            },
          ),
          _settingsTile(
            icon: Icons.language,
            iconColor: _positive,
            title: tr(context, 'language'),
            subtitle: _currentLanguageName(localeCtrl),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: LocaleController.supported
                        .any((l) => l.code == localeCtrl.languageCode)
                    ? localeCtrl.languageCode
                    : 'fr',
                icon: Icon(Icons.expand_more, color: _mutedIcon, size: 20),
                items: LocaleController.supported.map((l) {
                  return DropdownMenuItem(
                    value: l.code,
                    child: Text('${l.flag}  ${l.nativeName}',
                        style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (code) {
                  if (code != null) localeCtrl.setLocale(code);
                },
              ),
            ),
          ),

          // COMPTE
          _sectionHeader(tr(context, 'set_section_account')),
          _settingsTile(
            icon: Icons.info_outline,
            iconColor: _muted,
            title: tr(context, 'set_about'),
            subtitle: tr(context, 'set_version', {'v': '1.0.0'}),
            trailing: _chevron(),
            onTap: () => _showAbout(),
          ),
          _settingsTile(
            icon: Icons.delete_forever_outlined,
            iconColor: themed(context,
                light: AlanyaColors.error, dark: AlanyaColors.erreurNuit),
            title: tr(context, 'set_delete_account'),
            subtitle: tr(context, 'set_delete_account_sub'),
            trailing: _chevron(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(tr(context, 'set_logout_q')),
                    content: Text(
                        tr(context, 'set_logout_body')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr(context, 'cancel'))),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.read<AuthController>().logout();
                        },
                        child: Text(tr(context, 'set_logout_action'),
                            style: TextStyle(color: _danger)),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.logout, color: _danger),
              label: Text(tr(context, 'logout'), style: TextStyle(color: _danger)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(
                    color: themed(context,
                        light: Colors.red.shade200,
                        dark: AlanyaColors.erreurNuit.withValues(alpha: 0.35))),
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
              letterSpacing: 1.2)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: themed(context,
            light: Colors.white, dark: surfacesOf(context).surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: themed(context,
                light: AlanyaColors.grey200, dark: AlanyaColors.ligne),
            width: 0.5),
      ),
      child: child,
    );
  }

  // --- Couleurs theme-aware (le mode clair reste inchangé) ---
  Color get _muted =>
      themed(context, light: AlanyaColors.grey500, dark: AlanyaColors.craie2);
  Color get _mutedIcon =>
      themed(context, light: AlanyaColors.grey400, dark: AlanyaColors.craie2);
  Color get _accent => themed(context,
      light: AlanyaColors.terracotta, dark: AlanyaColors.terracottaNuit);
  Color get _positive => themed(context,
      light: AlanyaColors.forest, dark: AlanyaColors.indigoLight);
  Color get _danger =>
      themed(context, light: Colors.red, dark: AlanyaColors.erreurNuit);
  // Fond de la pastille ON/OFF à l'état éteint.
  Color get _chipOffBg => themed(context,
      light: AlanyaColors.grey200, dark: surfacesOf(context).surfaceHaute);

  Widget _chevron() => Icon(Icons.chevron_right,
      color: themed(context, light: Colors.grey, dark: AlanyaColors.craie2));

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
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: _muted))
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

  void _showThemePicker(ThemeController themeCtrl) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr(context, 'set_theme'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(height: 1),
          ...ChoixTheme.values.map((c) {
            final selected = themeCtrl.choix == c;
            return ListTile(
              leading: Icon(ThemeController.icone(c), color: _accent),
              title: Text(ThemeController.label(c)),
              // Sans sous-titre, « Nuit » et « Noir » ne se distinguent pas.
              subtitle: Text(
                ThemeController.description(c),
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              trailing: selected ? Icon(Icons.check, color: _accent) : null,
              onTap: () {
                Navigator.pop(ctx);
                themeCtrl.setChoix(c);
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
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
            Image.asset(
              "assets/images/app_icon.png",
              width: 72,
              height: 72,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    AlanyaColors.terracotta,
                    AlanyaColors.terracottaDark
                  ]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                    child:
                        Icon(Icons.chat_bubble, size: 36, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            const AlanyaWordmark(fontSize: 22, letterSpacing: 2),
            const SizedBox(height: 4),
            Text(tr(context, 'set_version', {'v': '1.0.0'}), style: TextStyle(color: _muted)),
            const SizedBox(height: 8),
            Text(tr(context, 'set_app_description'),
                style: TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 16),
            Text(tr(context, 'set_copyright'),
                style: TextStyle(color: _mutedIcon, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'close'))),
        ],
      ),
    );
  }
}
