import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_flow.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';

/// Shown after the user taps the reset link in their email. They set a new
/// password (entered twice, must match) before entering the app.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _authRepo = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _authRepo.updatePassword(_pw.text);
      passwordRecovery.value = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated — you\'re signed in.')),
      );
      context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _cancel() async {
    // Signing out clears the recovery flag, sending the router back to login.
    await _authRepo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthVideoBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const FadeSlideIn(child: BrandLogo(size: 72)),
                const SizedBox(height: AppSpacing.lg),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: GradientText(
                    'Set a new password',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: Text(
                    'Choose a new password for your account. Enter it twice '
                    'to confirm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: AuthCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthField(
                            controller: _pw,
                            label: 'New password',
                            icon: Icons.lock_outline,
                            obscure: true,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AuthField(
                            controller: _confirm,
                            label: 'Confirm new password',
                            icon: Icons.lock_outline,
                            obscure: true,
                            textInputAction: TextInputAction.done,
                            validator: (v) => v != _pw.text
                                ? 'Passwords do not match'
                                : null,
                            onFieldSubmitted: (_) =>
                                _busy ? null : _submit(),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AuthPrimaryButton(
                            loading: _busy,
                            label: 'Save password & continue',
                            onPressed: _submit,
                          ),
                          TextButton(
                            onPressed: _busy ? null : _cancel,
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
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
