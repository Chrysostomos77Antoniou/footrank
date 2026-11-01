import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/match/presentation/widgets/match_surfaces.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/match/presentation/widgets/roster_picker.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/theme/theme_controller.dart';

class CreateMatchRequestPage extends StatefulWidget {
  /// The captain's team id (required to create a request).
  final String teamId;

  /// Players chosen for the roster in the picker shown right after the team
  /// selection (null = whole team).
  final List<String>? initialRoster;

  /// Test hooks: stand-in repositories. Production uses the real ones.
  @visibleForTesting
  final MatchRepository? matchRepository;
  @visibleForTesting
  final TeamRepository? teamRepository;

  const CreateMatchRequestPage({
    super.key,
    required this.teamId,
    this.initialRoster,
    this.matchRepository,
    this.teamRepository,
  });

  @override
  State<CreateMatchRequestPage> createState() => _CreateMatchRequestPageState();
}

class _CreateMatchRequestPageState extends State<CreateMatchRequestPage>
    with ThemeRepaintMixin {
  final _formKey = GlobalKey<FormState>();
  late final MatchRepository _repo = widget.matchRepository ?? MatchRepository();
  late final TeamRepository _teamRepo = widget.teamRepository ?? TeamRepository();
  final _venueCtrl = TextEditingController();

  String? _city;
  DateTime? _date;
  TimeOfDay? _time;
  String _matchType = 'casual';
  // Matches are 5-a-side only.
  static const String _format = '5v5';
  bool _loading = false;

  // Roster tab: who is playing. Starts with the whole team selected.
  List<TeamMemberModel> _members = [];
  Set<String> _roster = {};

  @override
  void dispose() {
    _venueCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _roster = {...?widget.initialRoster};
    _loadMembers();
    // Sensible defaults so a captain can create a match in a couple of taps.
    final now = DateTime.now();
    final defaultHour = now.hour + 1;
    _time = TimeOfDay(hour: defaultHour % 24, minute: 0);
    // If "now + 1 hour" rolls past midnight, the default kick-off belongs to
    // tomorrow — otherwise the prefilled scheduledAt would be in the past.
    _date = defaultHour >= 24 ? now.add(const Duration(days: 1)) : now;
    _prefillCity();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await _teamRepo.fetchMembers(widget.teamId);
      if (!mounted) return;
      setState(() {
        _members = members;
        if (_roster.isEmpty) {
          _roster = members.map((m) => m.userId).toSet();
        }
      });
    } catch (_) {
      // The roster row just stays on its default; submit still validates.
    }
  }

  Future<void> _prefillCity() async {
    final team = await _teamRepo.fetchById(widget.teamId);
    if (mounted && _city == null) {
      setState(() => _city = canonicalCity(team.city));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    // Flutter's built-in keyboard-entry time picker places the cursor after
    // the existing digits instead of selecting them, so typing a new hour
    // means deleting the old one first. This custom dialog selects each
    // field's text the moment it's focused, so typing immediately overwrites.
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _TimeEntryDialog(initial: _time ?? TimeOfDay.now()),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_city == null) {
      showError(context, 'Please select a city');
      return;
    }
    if (_date == null || _time == null) {
      showError(context, 'Please pick a date and time');
      return;
    }
    if (_roster.length < kMinRoster) {
      showError(context,
          'Pick at least $kMinRoster players for your roster');
      return;
    }
    final scheduledAt = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );

    // Guard against scheduling a kick-off in the past (e.g. keeping today's
    // date but choosing an earlier time). Such requests would otherwise be
    // created and surface in opponents' discovery windows.
    if (scheduledAt.isBefore(DateTime.now())) {
      showError(context, 'Kick-off must be in the future');
      return;
    }

    setState(() => _loading = true);
    try {
      final conflict = await _repo.findSchedulingConflict(
        teamId: widget.teamId,
        scheduledAt: scheduledAt,
      );
      if (conflict != null) {
        if (mounted) {
          final t = TimeOfDay.fromDateTime(conflict).format(context);
          showError(context, 'Your team already has an open request or confirmed match '
                'for $t that day.',);
        }
        return;
      }

      final request = await _repo.createMatchRequest(
        teamId: widget.teamId,
        city: _city!,
        scheduledAt: scheduledAt,
        matchType: _matchType,
        venueText: cleanVenueInput(_venueCtrl.text),
        format: _format,
        rosterUserIds: _roster.toList(),
      );
      if (mounted) {
        showSuccess(context, 'Match request created');
        context.pop(request);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editRoster() async {
    if (_members.isEmpty) return;
    final picked = await showRosterSheet(
      context,
      members: _members,
      initial: _roster,
    );
    if (picked != null && mounted) setState(() => _roster = picked.toSet());
  }

  Widget _buildRosterRow() {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
      onTap: _editRoster,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.chip(context),
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.groups_outlined, color: AppColors.brand(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Roster',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${_roster.length} players selected',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.muted(context)),
                  ),
                ],
              ),
            ),
            Text('Edit',
                style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _date == null
        ? 'Select date'
        : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}';
    final timeLabel = _time == null ? 'Select time' : _time!.format(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Match',
          style: TextStyle(fontSize: 26, letterSpacing: -0.26),
        ),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _buildRosterRow()),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    child: Row(
                      children: [
                        Expanded(
                          child: _PickerField(
                            label: 'Date',
                            value: dateLabel,
                            icon: Icons.calendar_today,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PickerField(
                            label: 'Kick-off time',
                            value: timeLabel,
                            icon: Icons.access_time,
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 60),
                    child: DropdownButtonFormField<String>(
 icon: Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.muted(context)),
                      value: _city,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      items: kCities
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _city = v),
                      validator: (v) => v == null ? 'City is required' : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Where will you play?',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Type the venue name. Other captains will see it '
                          'exactly as you write it.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.muted(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 160),
                    child: TextFormField(
                      controller: _venueCtrl,
                      maxLength: kVenueMaxLength,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Venue name',
                        prefixIcon: Icon(Icons.stadium_outlined),
                      ),
                      validator: validateVenueInput,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 180),
                    child: VenuePreviewCard(
                      venueText: _venueCtrl.text,
                      whenLabel: [
                        dateLabel,
                        timeLabel,
                        if (_city != null) _city!,
                      ].join(' · '),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If the venue turns out to be full, you decide where to '
                    'play. Change it on the match and give the other captain '
                    'a call.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: AppColors.muted(context),
                        ),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Match Type',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          style: SegmentedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? AppColors.darkCard
                                : AppColors.lightCard,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSurface,
                            selectedBackgroundColor: AppColors.action,
                            selectedForegroundColor:
                                AppColors.onAction(context),
                            side: BorderSide(
                                color: AppColors.inputBorder(context)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppSemantic.controlRadius),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          segments: const [
                            ButtonSegment(
                                value: 'casual', label: Text('Casual')),
                            ButtonSegment(
                                value: 'ranked', label: Text('Ranked')),
                          ],
                          selected: {_matchType},
                          onSelectionChanged: (s) =>
                              setState(() => _matchType = s.first),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onAction(context),
                              ),
                            )
                          : const Text('Create Match Request'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 280),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.lime.withValues(alpha: 0.08)
                            : AppColors.lightChip,
                        borderRadius:
                            BorderRadius.circular(AppSemantic.controlRadius),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: AppColors.brand(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'After creating, tap "Find Opponents" to match with a '
                              'nearby team at a similar time and rating.',
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? AppColors.muted(context)
                                            : AppColors.ink,
                                      ),
                            ),
                          ),
                        ],
                      ),
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

/// A tappable, clearly-labelled date / time field (replaces the bare buttons).
class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSemantic.controlRadius);
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: Material(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppColors.inputBorder(context)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.brand(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AppColors.muted(context),
                          ),
                        ),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
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

/// Hour/minute entry dialog where tapping either field selects its existing
/// value, so typing a digit overwrites it immediately instead of appending
/// after a cursor left at the end (Flutter's built-in keyboard-entry time
/// picker does the latter, forcing a manual delete first).
class _TimeEntryDialog extends StatefulWidget {
  final TimeOfDay initial;
  const _TimeEntryDialog({required this.initial});

  @override
  State<_TimeEntryDialog> createState() => _TimeEntryDialogState();
}

class _TimeEntryDialogState extends State<_TimeEntryDialog> {
  late final _hourCtrl =
      TextEditingController(text: widget.initial.hour.toString().padLeft(2, '0'));
  late final _minuteCtrl = TextEditingController(
      text: widget.initial.minute.toString().padLeft(2, '0'));
  final _hourFocus = FocusNode();
  final _minuteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hourFocus.addListener(() {
      if (_hourFocus.hasFocus) _selectAll(_hourCtrl);
    });
    _minuteFocus.addListener(() {
      if (_minuteFocus.hasFocus) _selectAll(_minuteCtrl);
    });
  }

  void _selectAll(TextEditingController c) {
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final h = int.tryParse(_hourCtrl.text);
    final m = int.tryParse(_minuteCtrl.text);
    if (h == null || m == null || h > 23 || m > 59) {
      showError(context, 'Enter a valid time');
      return;
    }
    Navigator.pop(context, TimeOfDay(hour: h, minute: m));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: matchDialogColor(context),
      surfaceTintColor: Colors.transparent,
      shape: matchDialogShape(context),
      title: const Text('Enter kick-off time'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _hourCtrl,
              focusNode: _hourFocus,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(labelText: 'Hour', counterText: ''),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == 2) _minuteFocus.requestFocus();
              },
              onSubmitted: (_) => _minuteFocus.requestFocus(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: TextField(
              controller: _minuteCtrl,
              focusNode: _minuteFocus,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(labelText: 'Minute', counterText: ''),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
