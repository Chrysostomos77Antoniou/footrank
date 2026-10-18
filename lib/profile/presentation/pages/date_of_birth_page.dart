import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/profile/presentation/widgets/profile_fields.dart';
import 'package:footrank/routing/app_router.dart';

/// Minimum age to use FootRank. Mirrored server-side in
/// `set_my_date_of_birth` (which is the real gate).
const int kMinimumAge = 16;

/// Whole years between [dob] and [now].
int ageOn(DateTime dob, DateTime now) {
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age;
}

/// Mandatory step shown to every signed-in user who has no date of birth on
/// file: right after profile setup for new accounts, and on the next app open
/// for existing ones. The router keeps them here until it is saved, so there
/// is deliberately no back/skip.
class DateOfBirthPage extends StatefulWidget {
  const DateOfBirthPage({super.key});

  @override
  State<DateOfBirthPage> createState() => _DateOfBirthPageState();
}

class _DateOfBirthPageState extends State<DateOfBirthPage> {
  final _repo = ProfileRepository();
  DateTime? _dob;
  bool _saving = false;

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool get _underage =>
      _dob != null && ageOn(_dob!, DateTime.now()) < kMinimumAge;

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final dob = _dob;
    if (dob == null || _underage) return;
    setState(() => _saving = true);
    try {
      await _repo.saveMyDateOfBirth(dob);
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('DOB_UNDERAGE')) {
        setState(() {}); // the inline under-age notice is already shown
      } else if (msg.contains('DOB_INVALID')) {
        showError(context, 'Please choose a valid date of birth.');
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await AuthRepository().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fieldStyle = profileFieldTextStyle(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AmbientBackground(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'One last thing',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.26,
                            height: 1.2,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'When were you born? FootRank is for players aged '
                          '$kMinimumAge and over, so we need your date of '
                          'birth to continue.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: AppColors.muted(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        LabeledField(
                          label: 'Date of birth',
                          child: InkWell(
                            onTap: _saving ? null : _pick,
                            borderRadius: BorderRadius.circular(14),
                            child: IgnorePointer(
                              child: TextFormField(
                                key: ValueKey(_dob),
                                initialValue: _dob == null ? '' : _fmt(_dob!),
                                readOnly: true,
                                style: fieldStyle,
                                decoration: profileInputDecoration(
                                  context,
                                  icon: Icons.cake_outlined,
                                  hintText: 'Tap to choose',
                                  helperText:
                                      'Private. Only visible to FootRank admins.',
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_underage) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Sorry, you need to be at least $kMinimumAge to '
                            'use FootRank.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Continue',
                        loading: _saving,
                        onPressed: (_dob == null || _underage) ? null : _save,
                      ),
                      const SizedBox(height: 4),
                      AppButton(
                        label: 'Sign out',
                        variant: AppButtonVariant.ghost,
                        onPressed: _saving ? null : _signOut,
                      ),
                    ],
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
