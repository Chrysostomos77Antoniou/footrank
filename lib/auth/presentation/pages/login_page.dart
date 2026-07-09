import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _repo = AuthRepository();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _facebookLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _repo.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter your email above first, then tap "Forgot password?"',
          ),
        ),
      );
      return;
    }
    try {
      await _repo.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent \u2014 check your inbox.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await _repo.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _facebookLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthVideoBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Compresses spacing/sizing to fit shorter phone screens
              // (e.g. iPhone 13) without scrolling, instead of a single
              // fixed layout that only fits the tallest devices.
              final compact = constraints.maxHeight < 820;
              final logoSize = compact ? 68.0 : 100.0;
              final titleSize = compact ? 28.0 : 36.0;
              final gapXl = compact ? 16.0 : 34.0;
              final gapLg = compact ? 10.0 : 22.0;
              final gapSm = compact ? 3.0 : 6.0;
              final gapMd = compact ? 10.0 : 18.0;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: compact ? 4 : 16),
                      FadeSlideIn(child: BrandLogo(size: logoSize)),
                      SizedBox(height: gapLg),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: GradientText(
                          'FootRank',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      SizedBox(height: gapSm),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 140),
                        child: Text(
                          'Rank up. Find matches. Play.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      SizedBox(height: gapXl),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: AuthCard(
                          compact: compact,
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AuthGoogleButton(
                                  loading: _googleLoading,
                                  label: 'Continue with Google',
                                  onPressed: _signInWithGoogle,
                                ),
                                SizedBox(height: compact ? 6 : 10),
                                AuthGoogleButton(
                                  loading: _appleLoading,
                                  label: 'Continue with Apple',
                                  icon: Icons.apple,
                                  onPressed: _signInWithApple,
                                ),
                                SizedBox(height: compact ? 6 : 10),
                                AuthGoogleButton(
                                  loading: _facebookLoading,
                                  label: 'Continue with Facebook',
                                  icon: Icons.facebook,
                                  onPressed: _signInWithFacebook,
                                ),
                                SizedBox(height: gapMd),
                                const AuthOrDivider(),
                                SizedBox(height: gapMd),
                                AuthField(
                                  controller: _emailCtrl,
                                  label: 'Email',
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) =>
                                      v == null || !v.contains('@')
                                      ? 'Enter a valid email'
                                      : null,
                                ),
                                SizedBox(height: compact ? 8 : 14),
                                AuthField(
                                  controller: _passwordCtrl,
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  obscure: true,
                                  validator: (v) => v == null || v.length < 6
                                      ? 'Min 6 characters'
                                      : null,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _sendPasswordReset,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                    ),
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                                SizedBox(height: compact ? 2 : 8),
                                AuthPrimaryButton(
                                  loading: _loading,
                                  label: 'Login',
                                  onPressed: _signInWithEmail,
                                ),
                                TextButton(
                                  onPressed: () =>
                                      context.go(AppRoutes.register),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text(
                                    "Don't have an account? Sign Up",
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: gapMd),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 280),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Encrypted & secure sign-in',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 4 : 8),
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
