import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/app_snackbar.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/back_app_bar.dart';
import '../auth_repository.dart';
import 'setup_screen.dart';

/// Étape 2 : saisie du code OTP à 6 chiffres reçu par email.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.email});
  final String email;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = "";
  bool _loading = false;

  Future<void> _verify() async {
    if (_code.length != 6) {
      showAppSnackBar(tr(context, 'enter_6_digits'));
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await context.read<AuthRepository>().verify(widget.email, _code);
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SetupScreen(
            setupToken: result.setupToken,
            publicNumber: result.publicNumber,
          ),
        ),
      );
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    } catch (_) {
      showAppSnackBar(tr(context, 'server_unreachable'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await context.read<AuthRepository>().register(widget.email);
      showAppSnackBar(tr(context, 'new_code_sent'));
    } on ApiException catch (e) {
      showAppSnackBar(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: backAppBar(context, tr(context, 'confirmation')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                tr(context, 'enter_code'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Un code à 6 chiffres a été envoyé à ${widget.email}.",
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.center,
                child: PinCodeTextField(
                  appContext: context,
                  length: 6,
                  keyboardType: TextInputType.number,
                  animationType: AnimationType.fade,
                  onChanged: (v) => _code = v,
                  onCompleted: (v) {
                    _code = v;
                    _verify();
                  },
                  pinTheme: PinTheme(
                    shape: PinCodeFieldShape.box,
                    borderRadius: BorderRadius.circular(10),
                    fieldHeight: 52,
                    fieldWidth: 44,
                    activeColor: AppColors.terracotta,
                    selectedColor: AppColors.terracotta,
                    inactiveColor: AppColors.sand,
                    activeFillColor: Colors.white,
                    selectedFillColor: Colors.white,
                    inactiveFillColor: Colors.white,
                  ),
                  enableActiveFill: true,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _verify,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(tr(context, 'verify')),
              ),
              TextButton(
                onPressed: _loading ? null : _resend,
                child: Text(tr(context, 'resend_code')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
