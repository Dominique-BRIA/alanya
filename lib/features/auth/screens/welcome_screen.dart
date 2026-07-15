import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/alanya_theme.dart';
import '../../../widgets/motif_background.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeCtrl = context.watch<LocaleController>();

    return Scaffold(
      body: MotifBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // --- Logo avec brouillard progressif ---
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AlanyaColors.terracotta.withValues(alpha: 0.12),
                              AlanyaColors.terracotta.withValues(alpha: 0.04),
                              Colors.transparent,
                            ],
                            stops: const [0.3, 0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Image.asset(
                      "assets/images/logo.png",
                      width: 280,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.chat_bubble_rounded,
                        size: 120,
                        color: AlanyaColors.terracotta,
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AlanyaColors.terracotta.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'app_tagline'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AlanyaColors.ink),
                ),
                const Spacer(flex: 3),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: Text(tr(context, 'create_account')),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AlanyaColors.terracotta),
                    foregroundColor: AlanyaColors.terracotta,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(tr(context, 'have_account')),
                ),
                const SizedBox(height: 20),
                // --- Sélecteur de langue (dropdown comme dans le profil) ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AlanyaColors.grey200, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.language, size: 18, color: AlanyaColors.grey500),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: LocaleController.supported
                                    .any((l) => l.code == localeCtrl.languageCode)
                                ? localeCtrl.languageCode
                                : 'fr',
                            isExpanded: true,
                            icon: Icon(Icons.expand_more, color: AlanyaColors.grey400),
                            items: LocaleController.supported.map((l) {
                              return DropdownMenuItem(
                                value: l.code,
                                child: Text('${l.flag}  ${l.nativeName}'),
                              );
                            }).toList(),
                            onChanged: (code) {
                              if (code != null) localeCtrl.setLocale(code);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
