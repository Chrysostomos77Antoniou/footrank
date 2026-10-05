import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/profile/presentation/widgets/profile_fields.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/core/widgets/feedback.dart';

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
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The Pwr assessment quiz is still ahead -- it's the last mandatory step
  /// before the app lets a brand-new account in (a team can't be created or
  /// joined until it's done). The onboarding intent (create a team / free
  /// agent) stays saved and is honoured there once the quiz finishes, not
  /// here, so a user is never pushed straight into create-team before they've
  /// cleared the server-side gate.
  void _routeAfterSetup() {
    context.go(AppRoutes.pwrAssessment);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fieldStyle = profileFieldTextStyle(context);
    final iconDown = Icon(Icons.keyboard_arrow_down,
        size: 18, color: AppColors.muted(context));
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Set Up Your Profile',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.26,
                            height: 1.2,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: 0.5,
                            minHeight: 4,
                            backgroundColor: onSurface.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.action),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('STEP 1 OF 2', style: _stepLabelStyle(context)),
                            Text('ABOUT YOU', style: _stepLabelStyle(context)),
                          ],
                        ),
                        const SizedBox(height: 22),
                        FadeSlideIn(
                          child: Text(
                            'Tell us about yourself',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.18,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: LabeledField(
                            label: 'Full Name',
                            child: TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              style: fieldStyle,
                              decoration: profileInputDecoration(context),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Name is required'
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 100),
                          child: LabeledField(
                            label: 'Username',
                            child: TextFormField(
                              controller: _usernameCtrl,
                              style: fieldStyle,
                              decoration: profileInputDecoration(
                                context,
                                prefixText: '@',
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
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 140),
                          child: LabeledField(
                            label: 'Mobile Number',
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: fieldStyle.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                              decoration: profileInputDecoration(
                                context,
                                prefixText: '+357 ',
                                hintText: '99 123456',
                                helperText:
                                    'Used to confirm you and to reach you about matches',
                              ),
                              validator: _validatePhone,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 180),
                          child: LabeledField(
                            label: 'City',
                            child: DropdownButtonFormField<String>(
                              value: _city,
                              isExpanded: true,
                              style: fieldStyle,
                              icon: iconDown,
                              borderRadius: BorderRadius.circular(
                                  AppSemantic.controlRadius),
                              decoration: profileInputDecoration(
                                context,
                                verticalPadding: 14,
                              ),
                              items: kCities
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) => setState(() => _city = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 220),
                          child: LabeledField(
                            label: 'Preferred Position',
                            child: DropdownButtonFormField<String>(
                              value: _position,
                              isExpanded: true,
                              style: fieldStyle,
                              icon: iconDown,
                              borderRadius: BorderRadius.circular(
                                  AppSemantic.controlRadius),
                              decoration: profileInputDecoration(
                                context,
                                verticalPadding: 14,
                              ),
                              items: _positions
                                  .map((p) => DropdownMenuItem(
                                      value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (v) => setState(() => _position = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 260),
                  child: BrandButton(
                    label: 'Continue',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _stepLabelStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.muted(context),
    );
