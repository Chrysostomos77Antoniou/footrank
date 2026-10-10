import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/data/legal_versions.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/routing/app_router.dart';

/// Shown to any signed-in user who hasn't accepted the current Terms of
/// Service and Privacy Policy yet -- including people who just created an
/// account with Google, Apple or Facebook, who otherwise never see the
/// agreement checkbox from the register screen.
class AcceptTermsPage extends StatefulWidget {
  const AcceptTermsPage({super.key});

  @override
  State<AcceptTermsPage> createState() => _AcceptTermsPageState();
}

class _AcceptTermsPageState extends State<AcceptTermsPage> {
  final _repo = AuthRepository();
  bool _agreed = false;
  bool _saving = false;

  Future<void> _open(String path) async {
    await launchUrl(
      Uri.parse('${LegalVersions.baseUrl}/$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      await _repo.recordLegalConsent(source: 'consent_screen');
      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _repo.signOut();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Before you continue',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(
                    'Please review our Terms of Service and Privacy Policy. '
                    'They explain what data FootRank collects, why, who we '
                    'share it with, and your rights.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 20,
                    children: [
                      InkWell(
                        onTap: () => _open('terms.html'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Terms of Service', style: linkStyle),
                        ),
                      ),
                      InkWell(
                        onTap: () => _open('privacy.html'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Privacy Policy', style: linkStyle),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreed,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _agreed = v ?? false),
                    title: const Text(
                      'I have read and agree to the Terms of Service and '
                      'Privacy Policy, and I confirm I am at least 16 years '
                      'old.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_agreed && !_saving) ? _accept : null,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _saving ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
