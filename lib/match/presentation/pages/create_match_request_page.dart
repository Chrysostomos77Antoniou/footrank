import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/match/presentation/widgets/match_surfaces.dart';
import 'package:footrank/core/utils/maps_launcher.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/court_image_preview.dart';
import 'package:footrank/core/widgets/map_pill_button.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/court_model.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/theme/theme_controller.dart';

class CreateMatchRequestPage extends StatefulWidget {
  /// The captain's team id (required to create a request).
  final String teamId;
  const CreateMatchRequestPage({super.key, required this.teamId});

  @override
  State<CreateMatchRequestPage> createState() => _CreateMatchRequestPageState();
}

class _CreateMatchRequestPageState extends State<CreateMatchRequestPage>
    with ThemeRepaintMixin {
  final _formKey = GlobalKey<FormState>();
  final _repo = MatchRepository();
  final _teamRepo = TeamRepository();
  final _courtRepo = CourtRepository();

  String? _city;
  DateTime? _date;
  TimeOfDay? _time;
  String _matchType = 'casual';
  // Matches are 5-a-side only.
  static const String _format = '5v5';
  bool _loading = false;

  List<CourtModel> _courts = [];
  bool _courtsLoading = false;
  String? _selectedCourtId;
  final _courtPageController = PageController(viewportFraction: 0.86);
  int _courtPage = 0;

  @override
  void dispose() {
    _courtPageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Sensible defaults so a captain can create a match in a couple of taps.
    final now = DateTime.now();
    final defaultHour = now.hour + 1;
    _time = TimeOfDay(hour: defaultHour % 24, minute: 0);
    // If "now + 1 hour" rolls past midnight, the default kick-off belongs to
    // tomorrow — otherwise the prefilled scheduledAt would be in the past.
    _date = defaultHour >= 24 ? now.add(const Duration(days: 1)) : now;
    _prefillCity();
  }

  Future<void> _prefillCity() async {
    final team = await _teamRepo.fetchById(widget.teamId);
    if (mounted && _city == null) {
      setState(() => _city = canonicalCity(team.city));
      _loadCourts();
    }
  }

  Future<void> _loadCourts() async {
    final city = _city;
    if (city == null) return;
    setState(() => _courtsLoading = true);
    try {
      final courts = await _courtRepo.fetchCourtsForCity(city);
      if (!mounted) return;
      setState(() {
        _courts = courts;
        _selectedCourtId = null;
        _courtsLoading = false;
        _courtPage = 0;
      });
      if (_courtPageController.hasClients) {
        _courtPageController.jumpToPage(0);
      }
    } catch (_) {
      if (mounted) setState(() => _courtsLoading = false);
    }
  }

  void _selectCourt(String courtId) {
    setState(() {
      _selectedCourtId = _selectedCourtId == courtId ? null : courtId;
    });
  }

  Future<void> _openMaps(CourtModel c) =>
      openInMaps(name: c.name, address: c.address, city: c.city);

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
    if (!_formKey.currentState!.validate()) return;
    if (_city == null) {
      showError(context, 'Please select a city');
      return;
    }
    if (_date == null || _time == null) {
      showError(context, 'Please pick a date and time');
      return;
    }
    if (_selectedCourtId == null) {
      showError(context, 'Pick a court');
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
        courtId: _selectedCourtId!,
        format: _format,
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

  Widget _buildCourtPicker() {
    if (_courtsLoading) {
      return const LoadingView();
    }
    if (_courts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.chip(context),
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
        ),
        child: Text(
          _city == null
              ? 'Select a city to see courts.'
              : 'No courts listed yet for $_city.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.muted(context)),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 330,
          child: PageView.builder(
            controller: _courtPageController,
            onPageChanged: (i) => setState(() => _courtPage = i),
            itemCount: _courts.length,
            itemBuilder: (context, i) => _buildCourtCard(_courts[i]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_courts.length, (i) {
            final active = i == _courtPage;
            return AnimatedContainer(
              duration: reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: active
                    ? AppColors.brand(context)
                    : AppColors.onChip(context).withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.35
                            : 0.25),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCourtCard(CourtModel c) {
    final picked = c.id == _selectedCourtId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkCard : AppColors.lightCard;
    final fill = picked
        ? Color.alphaBlend(
            AppColors.action.withValues(alpha: isDark ? 0.08 : 0.2), base)
        : base;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: picked ? AppColors.brand(context) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Capped square: sized off the card's own width but never taller
            // than 184 -- a true square that still leaves guaranteed room for
            // the name/address/button below inside the fixed carousel height.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth < 184
                      ? constraints.maxWidth
                      : 184.0;
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => showCourtImagePreview(
                            context,
                            name: c.name,
                            imageUrl: c.imageUrl,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (c.imageUrl != null)
                                Image.network(
                                  c.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _courtImagePlaceholder(),
                                )
                              else
                                _courtImagePlaceholder(),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: MapPillButton(
                                    onPressed: () => _openMaps(c)),
                              ),
                              if (picked)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: CircleAvatar(
                                    radius: 15,
                                    backgroundColor: AppColors.brand(context),
                                    child: Icon(Icons.check,
                                        color: AppColors.onBrand(context),
                                        size: 18),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (c.address != null)
                    Text(
                      c.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted(context),
                          ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: picked
                        ? OutlinedButton.icon(
                            onPressed: () => _selectCourt(c.id),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSemantic.controlRadius),
                              ),
                              side: isDark
                                  ? BorderSide(
                                      color: Colors.white
                                          .withValues(alpha: 0.24))
                                  : const BorderSide(
                                      color: AppColors.limeDeep, width: 1.5),
                              textStyle: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Remove'),
                          )
                        : FilledButton.icon(
                            onPressed: () => _selectCourt(c.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSemantic.controlRadius),
                              ),
                              textStyle: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Select this court'),
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

  Widget _courtImagePlaceholder() => Container(
    color: AppColors.chip(context),
    child: Icon(
      Icons.sports_soccer,
      size: 56,
      color: AppColors.brand(context).withValues(alpha: 0.6),
    ),
  );

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
                      onChanged: (v) {
                        setState(() => _city = v);
                        _loadCourts();
                      },
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
                          'Pick a Court',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'This is the court captains will see on your open request.',
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
                      child: _buildCourtPicker()),
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
