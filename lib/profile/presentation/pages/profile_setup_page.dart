import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _repo = ProfileRepository();
  String? _city;
  String? _position;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Sign in with Apple (and Google/Facebook) already hand us the user's
    // name on first authorization -- Apple's review guidelines require we
    // not make the user re-type it. Pre-fill (still editable) instead of
    // starting from a blank field.
    final meta = SupabaseService.client.auth.currentUser?.userMetadata;
    final given = meta?['given_name'] as String?;
    final family = meta?['family_name'] as String?;
    final prefillName =
        (meta?['full_name'] as String?) ??
        (meta?['name'] as String?) ??
        [given, family].whereType<String>().join(' ').trim();
    if (prefillName.isNotEmpty) {
      _nameCtrl.text = prefillName;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// Cyprus mobile: 8 digits starting with 9, with or without the +357 /
  /// 00357 prefix. Mirrors the server-side check so the user gets the error
  /// inline instead of after a round-trip.
  static String? _validatePhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    var d = digits;
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 8 && d.startsWith('9')) d = '357$d';
    if (!RegExp(r'^3579[0-9]{7}$').hasMatch(d)) {
      return 'Enter a valid Cyprus mobile, e.g. 99 123456';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _repo.createProfile(
        name: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        city: _city,
        position: _position,
      );
      if (mounted) _routeAfterSetup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A brand-new user has no team yet, so honour the intent they chose during
  /// onboarding: take them straight into creating a team (or the free-agents
  /// board) on top of Home, rather than dropping them on an empty Home screen.
  /// The intent is consumed once. When none was set we keep the old behaviour.
  void _routeAfterSetup() {
    final intent = OnboardingPrefs.postSetupIntent;
    // Clear so it never triggers again on later setups/sessions.
    OnboardingPrefs.setPostSetupIntent(null);

    context.go(AppRoutes.home);

    String? target;
    if (intent == OnboardingIntent.createTeam) {
      target = AppRoutes.createTeam;
    } else if (intent == OnboardingIntent.freeAgent) {
      target = AppRoutes.freeAgents;
    }
    if (target == null) return;

    // Push after Home has settled so the user can back out to Home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(target!);
    });
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('PHONE_TAKEN') ||
        msg.contains('uq_user_contacts_phone_normalized')) {
      return 'That phone number is already linked to another account';
    }
    if (msg.contains('PHONE_INVALID')) {
      return 'Enter a valid Cyprus mobile, e.g. 99 123456';
    }
    if (msg.contains('PHONE_REQUIRED')) {
      return 'Phone number is required';
    }
    if (msg.contains('duplicate') || msg.contains('unique')) {
      return 'That username is already taken';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tell us about yourself',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Username is required';
                    }
                    if (v.trim().length < 3) {
                      return 'At least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixText: '+357 ',
                    hintText: '99 123456',
                    helperText: 'Used to confirm you and to reach you about matches',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _city,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                  items: kCities
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _city = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _position,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Position',
                    border: OutlineInputBorder(),
                  ),
                  items: _positions
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _position = v),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
