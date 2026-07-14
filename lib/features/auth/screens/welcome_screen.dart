import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
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
                    color: AppColors.terracotta,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'app_tagline'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
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
                    side: const BorderSide(color: AppColors.terracotta),
                    foregroundColor: AppColors.terracotta,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(tr(context, 'have_account')),
                ),
                const SizedBox(height: 16),
                Text(tr(context, 'language'), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: LocaleController.supported.map((l) {
                    final selected = localeCtrl.languageCode == l.code;
                    return ChoiceChip(
                      label: Text('${l.flag} ${l.code.toUpperCase()}'),
                      selected: selected,
                      onSelected: (_) => localeCtrl.setLocale(l.code),
                      selectedColor: AppColors.terracotta.withOpacity(0.2),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected ? AppColors.terracotta : Colors.black87,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }).toList(),
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
