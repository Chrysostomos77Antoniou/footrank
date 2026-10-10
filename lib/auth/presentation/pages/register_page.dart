import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/data/legal_versions.dart';
import 'package:footrank/auth/presentation/widgets/auth_video_background.dart';
import 'package:footrank/auth/presentation/widgets/auth_widgets.dart';
import 'package:footrank/core/utils/password_strength.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/core/widgets/feedback.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
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
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openLegal(String path) async {
    final uri = Uri.parse(
      '${LegalVersions.baseUrl}/$path',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _requireAgreement() {
    if (_agreedToTerms) return true;
    showError(context, 'Please agree to the Terms of Service and Privacy Policy first',);
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
        showSuccess(context, 'Check your email to confirm sign up');
        context.go(AppRoutes.login);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
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
        showError(context, e);
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
        showError(context, e);
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
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _facebookLoading = false);
    }
  }

  Widget _termsRow(AuthTone tone) {
    const base = TextStyle(fontSize: 12, height: 1.45);
    final linkStyle = base.copyWith(
      color: tone.dark ? tone.text : tone.link,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    final textStyle = base.copyWith(color: tone.secondary);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSemantic.minTapTarget),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _agreedToTerms,
                activeColor: tone.dark ? AppColors.lime : AppColors.limeDeeper,
                checkColor: tone.dark ? AppColors.navy : Colors.white,
                side: BorderSide(color: tone.secondary, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (v) =>
                    setState(() => _agreedToTerms = v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('I agree to the ', style: textStyle),
                  InkWell(
                    onTap: () => _openLegal('terms.html'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('Terms of Service', style: linkStyle),
                    ),
                  ),
                  Text(' and ', style: textStyle),
                  InkWell(
                    onTap: () => _openLegal('privacy.html'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('Privacy Policy', style: linkStyle),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      const FadeSlideIn(
                        child: AuthBrandBlock(
                          title: 'Create Account',
                          subtitle: 'Join the league.',
                          badgeSize: 52,
                          titleSize: 26,
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
                                      _termsRow(tone),
                                      const SizedBox(height: 6),
                                      AuthGoogleButton(
                                        loading: _googleLoading,
                                        label: 'Sign up with Google',
                                        onPressed: _signInWithGoogle,
                                      ),
                                      SizedBox(height: gapSocial),
                                      AuthGoogleButton(
                                        loading: _appleLoading,
                                        label: 'Sign up with Apple',
                                        icon: Icons.apple,
                                        onPressed: _signInWithApple,
                                      ),
                                      SizedBox(height: gapSocial),
                                      AuthGoogleButton(
                                        loading: _facebookLoading,
                                        label: 'Sign up with Facebook',
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
                                            v == null || !v.contains('@')
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
                                        // newPassword (not password) so the OS
                                        // offers to *generate* a strong one
                                        // here, since this is an account
                                        // creation form.
                                        autofillHints: const [
                                          AutofillHints.newPassword,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) =>
                                            _signUpWithEmail(),
                                        validator: passwordStrengthError,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          2,
                                          6,
                                          2,
                                          AppSpacing.md,
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
                                      AuthPrimaryButton(
                                        loading: _loading,
                                        label: 'Sign Up',
                                        onPressed: _signUpWithEmail,
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      TextButton(
                                        onPressed: () =>
                                            context.go(AppRoutes.login),
                                        style: TextButton.styleFrom(
                                          foregroundColor: tone.secondary,
                                          minimumSize: const Size(44, 44),
                                        ),
                                        child: Text.rich(
                                          TextSpan(
                                            text: 'Already have an account? ',
                                            style: TextStyle(
                                              color: tone.secondary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'Login',
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
