import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/profile/data/profile_repository.dart';
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
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  final _repo = ProfileRepository();
  late int _year;
  int _month = 1;
  int _day = 1;
  // Continue stays disabled until the user actually scrolls a wheel, so the
  // starting position can never be saved as a made-up birthday.
  bool _touched = false;
  bool _saving = false;

  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _yearCtrl;

  late final int _firstYear;
  late final int _lastYear;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _lastYear = now.year;
    _firstYear = 1920;
    _year = now.year - 25;
    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
    _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _yearCtrl = FixedExtentScrollController(initialItem: _year - _firstYear);
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  int _daysIn(int month, int year) => DateTime(year, month + 1, 0).day;

  DateTime get _dob => DateTime(_year, _month, _day);

  bool get _future => _dob.isAfter(DateTime.now());

  bool get _underage =>
      _touched && !_future && ageOn(_dob, DateTime.now()) < kMinimumAge;

  void _changed({int? day, int? month, int? year}) {
    setState(() {
      _touched = true;
      if (day != null) _day = day;
      if (month != null) _month = month;
      if (year != null) _year = year;
      final max = _daysIn(_month, _year);
      if (_day > max) {
        _day = max;
        _dayCtrl.jumpToItem(_day - 1);
      }
    });
  }

  Future<void> _save() async {
    if (!_touched || _underage || _future) return;
    final dob = _dob;
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

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: 42,
      magnification: 1.08,
      useMagnifier: true,
      squeeze: 1.1,
      selectionOverlay: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.brand(context).withValues(alpha: 0.12),
        ),
      ),
      onSelectedItemChanged: onChanged,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(
              label(i),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
                        SizedBox(
                          height: 210,
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _wheel(
                                  controller: _dayCtrl,
                                  count: _daysIn(_month, _year),
                                  label: (i) => '${i + 1}',
                                  onChanged: (i) => _changed(day: i + 1),
                                ),
                              ),
                              Expanded(
                                flex: 6,
                                child: _wheel(
                                  controller: _monthCtrl,
                                  count: 12,
                                  label: (i) => _months[i],
                                  onChanged: (i) => _changed(month: i + 1),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: _wheel(
                                  controller: _yearCtrl,
                                  count: _lastYear - _firstYear + 1,
                                  label: (i) => '${_firstYear + i}',
                                  onChanged: (i) =>
                                      _changed(year: _firstYear + i),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          !_touched
                              ? 'Scroll each column to choose'
                              : _future
                                  ? 'That date is in the future'
                                  : '${_dob.day} ${_months[_dob.month - 1]} ${_dob.year}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _touched && !_future
                                ? onSurface
                                : AppColors.muted(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Private. Only visible to FootRank admins.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted(context),
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
                        onPressed: (!_touched || _underage || _future) ? null : _save,
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
