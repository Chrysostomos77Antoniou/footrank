import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/core/widgets/feedback.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  final _repo = AuthRepository();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _facebookLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Google Play's reviewer account is given as the plain username
  /// `app_reviewer` (the Play Console field isn't email-validated), so map
  /// it to the real account email.
  static String _resolveLoginId(String id) =>
      id.toLowerCase() == 'app_reviewer' ? 'app_reviewer@footrank.app' : id;

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _repo.signIn(
        email: _resolveLoginId(_emailCtrl.text.trim()),
        password: _passwordCtrl.text,
      );
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showError(context, 'Enter your email above first, then tap "Forgot password?"',);
      return;
    }
    try {
      await _repo.resetPassword(email);
      if (mounted) {
        showSuccess(context, 'Password reset email sent \u2014 check your inbox.');
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await _repo.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _appleLoading = true);
    try {
      await _repo.signInWithApple();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() => _facebookLoading = true);
    try {
      await _repo.signInWithFacebook();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _facebookLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: AuthVideoBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Tightens the header on short phones; the page scrolls if the
              // content is still taller than the screen.
              final compact = constraints.maxHeight < 700;
              final topPad = compact ? 4.0 : 12.0;
              final gapHeader = compact ? 12.0 : 24.0;
              final gapSocial = compact ? 6.0 : 10.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  topPad,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - topPad - AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeSlideIn(
                        child: AuthBrandBlock(
                          title: 'FootRank',
                          subtitle: 'Rank up. Find matches. Play.',
                          badgeSize: compact ? 52 : 64,
                        ),
                      ),
                      SizedBox(height: gapHeader),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: AuthCard(
                          compact: compact,
                          child: Form(
                            key: _formKey,
                            child: AutofillGroup(
                              child: Builder(
                                builder: (context) {
                                  final tone = AuthTone.of(context);
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AuthGoogleButton(
                                        loading: _googleLoading,
                                        label: 'Continue with Google',
                                        onPressed: _signInWithGoogle,
                                      ),
                                      SizedBox(height: gapSocial),
                                      AuthGoogleButton(
                                        loading: _appleLoading,
                                        label: 'Continue with Apple',
                                        icon: Icons.apple,
                                        onPressed: _signInWithApple,
                                      ),
                                      SizedBox(height: gapSocial),
                                      AuthGoogleButton(
                                        loading: _facebookLoading,
                                        label: 'Continue with Facebook',
                                        icon: Icons.facebook,
                                        onPressed: _signInWithFacebook,
                                      ),
                                      const SizedBox(height: 14),
                                      const AuthOrDivider(),
                                      const SizedBox(height: 14),
                                      AuthField(
                                        controller: _emailCtrl,
                                        label: 'Email',
                                        icon: Icons.email_outlined,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.email,
                                        ],
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) =>
                                            _passwordFocus.requestFocus(),
                                        validator: (v) =>
                                            v == null ||
                                                !(v.contains('@') ||
                                                    v.trim().toLowerCase() ==
                                                        'app_reviewer')
                                            ? 'Enter a valid email'
                                            : null,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      AuthField(
                                        controller: _passwordCtrl,
                                        focusNode: _passwordFocus,
                                        label: 'Password',
                                        icon: Icons.lock_outline,
                                        obscure: true,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) =>
                                            _signInWithEmail(),
                                        validator: (v) =>
                                            v == null || v.length < 6
                                            ? 'Min 6 characters'
                                            : null,
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _sendPasswordReset,
                                          style: TextButton.styleFrom(
                                            foregroundColor: dark
                                                ? tone.secondary
                                                : tone.link,
                                            minimumSize: const Size(44, 44),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.xxs,
                                            ),
                                            textStyle: TextStyle(
                                              fontSize: 13,
                                              fontWeight: dark
                                                  ? FontWeight.w600
                                                  : FontWeight.w700,
                                            ),
                                          ),
                                          child: const Text('Forgot password?'),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      AuthPrimaryButton(
                                        loading: _loading,
                                        label: 'Login',
                                        onPressed: _signInWithEmail,
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      TextButton(
                                        onPressed: () =>
                                            context.go(AppRoutes.register),
                                        style: TextButton.styleFrom(
                                          foregroundColor: tone.secondary,
                                          minimumSize: const Size(44, 44),
                                        ),
                                        child: Text.rich(
                                          TextSpan(
                                            text: "Don't have an account? ",
                                            style: TextStyle(
                                              color: tone.secondary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'Sign Up',
                                                style: TextStyle(
                                                  color: tone.link,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 280),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: dark
                                  ? const Color(0xFFC5CED6)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Encrypted & secure sign-in',
                              style: TextStyle(
                                color: dark
                                    ? const Color(0xFFC5CED6)
                                    : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
