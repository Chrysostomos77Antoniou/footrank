import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _repo = AuthRepository();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _facebookLoading = false;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLegal(String path) async {
    final uri = Uri.parse(
      'https://chrysostomos77antoniou.github.io/footrank/$path',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _requireAgreement() {
    if (_agreedToTerms) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Please agree to the Terms of Service and Privacy Policy first',
        ),
      ),
    );
    return false;
  }

  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_requireAgreement()) return;
    setState(() => _loading = true);
    try {
      final res = await _repo.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      if (res.session != null) {
        context.go(AppRoutes.profileSetup);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your email to confirm sign up')),
        );
        context.go(AppRoutes.login);
      }
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

  Future<void> _signInWithGoogle() async {
    if (!_requireAgreement()) return;
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
    if (!_requireAgreement()) return;
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
    if (!_requireAgreement()) return;
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
              final logoSize = compact ? 60.0 : 100.0;
              final titleSize = compact ? 24.0 : 30.0;
              final gapXl = compact ? 12.0 : 34.0;
              final gapLg = compact ? 8.0 : 22.0;
              final gapSm = compact ? 3.0 : 6.0;
              final gapMd = compact ? 8.0 : 18.0;
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
                          'Create Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      SizedBox(height: gapSm),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 140),
                        child: Text(
                          'Join the league.',
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _agreedToTerms,
                                        onChanged: (v) => setState(
                                          () => _agreedToTerms = v ?? false,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'I agree to the ',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () =>
                                                _openLegal('terms.html'),
                                            child: const Text(
                                              'Terms of Service',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            ' and ',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () =>
                                                _openLegal('privacy.html'),
                                            child: const Text(
                                              'Privacy Policy',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: gapMd),
                                AuthGoogleButton(
                                  loading: _googleLoading,
                                  label: 'Sign up with Google',
                                  onPressed: _signInWithGoogle,
                                ),
                                SizedBox(height: compact ? 6 : 10),
                                AuthGoogleButton(
                                  loading: _appleLoading,
                                  label: 'Sign up with Apple',
                                  icon: Icons.apple,
                                  onPressed: _signInWithApple,
                                ),
                                SizedBox(height: compact ? 6 : 10),
                                AuthGoogleButton(
                                  loading: _facebookLoading,
                                  label: 'Sign up with Facebook',
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
                                  validator: (v) => v == null || v.length < 8
                                      ? 'Min 8 characters'
                                      : null,
                                ),
                                SizedBox(height: compact ? 10 : 22),
                                AuthPrimaryButton(
                                  loading: _loading,
                                  label: 'Sign Up',
                                  onPressed: _signUpWithEmail,
                                ),
                                TextButton(
                                  onPressed: () => context.go(AppRoutes.login),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text(
                                    'Already have an account? Login',
                                  ),
                                ),
                              ],
                            ),
                          ),
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
