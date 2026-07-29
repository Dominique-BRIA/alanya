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
                    // Halo réduit dans la même proportion que le logo (260 → 173)
                    // pour conserver le rapport d'origine entre la lueur et la bulle.
                    // Le Positioned englobant a été retiré : tous ses décalages
                    // étaient nuls, et un enfant positionné ne participe pas au
                    // dimensionnement du Stack. Sans lui, alignment: center
                    // centre réellement le halo sur le logo.
                    Container(
                      width: 173,
                      height: 173,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accentOf(context).withValues(alpha: 0.12),
                            accentOf(context).withValues(alpha: 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.3, 0.6, 1.0],
                        ),
                      ),
                    ),
                    Image.asset(
                      "assets/images/logo.png",
                      width: 187,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.chat_bubble_rounded,
                        size: 120,
                        color: accentOf(context),
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
                        accentOf(context).withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'app_tagline'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: themed(context, light: AlanyaColors.ink, dark: AlanyaColors.craie)),
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
                    side: BorderSide(color: accentOf(context)),
                    foregroundColor: accentOf(context),
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
                    color: themed(context, light: Colors.white, dark: AlanyaColors.nuit2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: themed(context, light: AlanyaColors.grey200, dark: AlanyaColors.ligne), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.language, size: 18, color: mutedOf(context, AlanyaColors.grey500)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: LocaleController.supported
                                    .any((l) => l.code == localeCtrl.languageCode)
                                ? localeCtrl.languageCode
                                : 'fr',
                            isExpanded: true,
                            icon: Icon(Icons.expand_more, color: mutedOf(context, AlanyaColors.grey400)),
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
