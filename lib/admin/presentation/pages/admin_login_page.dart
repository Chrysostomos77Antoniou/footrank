import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/services/supabase_service.dart';

/// The one account allowed into this panel -- fixed rather than typed, since
/// there's exactly one intended admin. Anyone without the matching password
/// for *this specific account* is rejected by Supabase Auth itself; even a
/// correct password for a different account would still fail the is_admin
/// check right after.
const _adminEmail = 'tomisapoelcity@gmail.com';

/// Sign-in gate for the admin panel. Password-only -- the identity is fixed
/// above, so there's nothing else to ask for. Still gated by `is_admin`
/// after a successful sign-in, same as before.
class AdminLoginPage extends StatefulWidget {
  final VoidCallback onSignedIn;
  const AdminLoginPage({super.key, required this.onSignedIn});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _adminRepo = AdminRepository();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.client.auth.signInWithPassword(
        email: _adminEmail,
        password: _password.text,
      );
      final isAdmin = await _adminRepo.isCurrentUserAdmin();
      if (!isAdmin) {
        await SupabaseService.client.auth.signOut();
        throw StateError('This account is not authorized for admin access.');
      }
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: FadeSlideIn(
                child: GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AdminLogo(size: 64)),
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: GradientText(
                            'FootRank Admin',
                            style: Theme.of(context).textTheme.displayMedium!.copyWith(
                              fontSize: 26,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Center(
                          child: Text(
                            'Enter your password to continue',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        TextFormField(
                          controller: _password,
                          autofocus: true,
                          obscureText: true,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.danger,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        BrandButton(
                          label: 'Sign in',
                          loading: _loading,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
