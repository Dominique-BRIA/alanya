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
                const SizedBox(height: 16),
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
                // --- Sélecteur de langue (liste) ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AlanyaColors.grey200, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Row(
                          children: [
                            Icon(Icons.language, size: 18, color: AlanyaColors.grey500),
                            const SizedBox(width: 8),
                            Text(
                              tr(context, 'language'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AlanyaColors.grey500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...LocaleController.supported.map((l) {
                        final selected = localeCtrl.languageCode == l.code;
                        return InkWell(
                          onTap: () => localeCtrl.setLocale(l.code),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 11),
                            color: selected
                                ? AlanyaColors.terracotta.withValues(alpha: 0.06)
                                : Colors.transparent,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l.nativeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: selected
                                          ? AlanyaColors.terracotta
                                          : AlanyaColors.ink,
                                    ),
                                  ),
                                ),
                                Text(
                                  l.code.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: selected
                                        ? AlanyaColors.terracotta
                                        : AlanyaColors.grey400,
                                  ),
                                ),
                                if (selected) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.check,
                                      size: 18,
                                      color: AlanyaColors.terracotta),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
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
