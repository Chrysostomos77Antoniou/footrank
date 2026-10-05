import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_flow.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/password_strength.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/core/widgets/feedback.dart';

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
      showSuccess(context, 'Password updated — you\'re signed in.');
      context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _cancel() async {
    // Signing out clears the recovery flag, sending the router back to login.
    await _authRepo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(left: 0, right: 0, bottom: 0, child: AuthPitchFloor()),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  AuthPitchHero(
                    height: safeTop + 208,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xxl,
                        safeTop,
                        AppSpacing.xxl,
                        0,
                      ),
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: FadeSlideIn(
                          child: AuthBrandBlock(
                            title: 'Set a new password',
                            subtitle:
                                'Choose a new password for your account. '
                                'Enter it twice to confirm.',
                            badgeSize: 56,
                            titleSize: 26,
                            overVideo: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -AppSpacing.xl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: AuthCard(
                          frosted: false,
                          child: Form(
                            key: _formKey,
                            child: Builder(
                              builder: (context) {
                                final tone = AuthTone.of(context);
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AuthField(
                                      controller: _pw,
                                      label: 'New password',
                                      icon: Icons.lock_outline,
                                      obscure: true,
                                      textInputAction: TextInputAction.next,
                                      validator: passwordStrengthError,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        2,
                                        6,
                                        2,
                                        14,
                                      ),
                                      child: Text(
                                        '8+ characters, with upper & '
                                        'lowercase letters, a number, and a '
                                        'symbol',
                                        style: TextStyle(
                                          color: tone.hint,
                                          fontSize: 11,
                                          height: 14 / 11,
                                        ),
                                      ),
                                    ),
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
                                    const SizedBox(height: 20),
                                    AuthPrimaryButton(
                                      loading: _busy,
                                      label: 'Save password & continue',
                                      onPressed: _submit,
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    TextButton(
                                      onPressed: _busy ? null : _cancel,
                                      style: TextButton.styleFrom(
                                        foregroundColor: dark
                                            ? tone.text
                                            : AppColors.limeDeep,
                                        minimumSize: const Size(44, 44),
                                        textStyle: TextStyle(
                                          fontSize: 14,
                                          fontWeight: dark
                                              ? FontWeight.w600
                                              : FontWeight.w700,
                                        ),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
