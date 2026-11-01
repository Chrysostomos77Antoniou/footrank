import 'package:flutter/material.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/match/presentation/widgets/match_formatters.dart';

/// The filters of the Opponents tab.
///
/// Closed, it is a single line that says what you are looking at ("Larnaca ·
/// Any type · Any date"); open, it shows the controls. The old version printed
/// four stacked fields between you and the first result -- most visits never
/// change a thing, so the controls wait until asked for.
///
/// Motion, on purpose: the panel eases open over 200ms with the standard curve
/// and the chevron turns with it. Nothing else moves. Under "reduce motion" it
/// just opens.
class OpponentFilters extends StatefulWidget {
  final String city;
  final DateTime? date;
  final TimeOfDay? time;

  /// null = any, otherwise 'casual' or 'ranked'.
  final String? matchType;

  /// 0 = any Pitch Power.
  final int powerRange;

  /// True when something differs from the defaults (the team's own city, no
  /// other narrowing); shows the reset action.
  final bool isFiltered;

  final ValueChanged<String> onCityChanged;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<TimeOfDay?> onTimeChanged;
  final ValueChanged<String?> onMatchTypeChanged;
  final ValueChanged<int> onPowerRangeChanged;
  final VoidCallback onReset;

  const OpponentFilters({
    super.key,
    required this.city,
    required this.date,
    required this.time,
    required this.matchType,
    required this.powerRange,
    required this.isFiltered,
    required this.onCityChanged,
    required this.onDateChanged,
    required this.onTimeChanged,
    required this.onMatchTypeChanged,
    required this.onPowerRangeChanged,
    required this.onReset,
  });

  @override
  State<OpponentFilters> createState() => _OpponentFiltersState();
}

class _OpponentFiltersState extends State<OpponentFilters> {
  static const _types = <String?>[null, 'casual', 'ranked'];
  static const _maxPowerRange = 500.0;

  bool _expanded = false;

  /// The slider's position while a finger is on it. The list is only reloaded
  /// when the finger lifts, not on every notch it passes.
  double? _dragRange;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.date ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) widget.onDateChanged(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: widget.time ?? TimeOfDay.now(),
    );
    if (picked != null) widget.onTimeChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final summary = describeOpponentFilters(
      city: widget.city,
      matchType: widget.matchType,
      date: widget.date,
      hour: widget.time?.hour,
      minute: widget.time?.minute,
      powerRange: widget.powerRange,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSemantic.screenPadding,
        vertical: AppSemantic.rowGap / 2,
      ),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              hint: _expanded ? 'Hide filters' : 'Show filters',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(AppSemantic.cardRadius),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSemantic.minTapTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSemantic.cardPadding,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: AppIconSize.sm,
                            color: AppColors.brand(context),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: still ? Duration.zero : AppMotion.quick,
                            curve: AppMotion.standard,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            MotionSize(
              child: _expanded
                  ? _buildPanel(context)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final range = _dragRange ?? widget.powerRange.toDouble();
    final rangeLabel = range.round() == 0 ? 'Any' : '±${range.round()} PWR';
    final date = widget.date;
    final time = widget.time;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSemantic.cardPadding,
        0,
        AppSemantic.cardPadding,
        AppSemantic.cardPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: AppSemantic.borderWidth),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Match type',
            style: theme.textTheme.labelMedium?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          FilterPills(
            index: _types.indexOf(widget.matchType).clamp(0, _types.length - 1),
            items: const [
              FilterPillItem('Any'),
              FilterPillItem('Casual'),
              FilterPillItem('Ranked'),
            ],
            padding: EdgeInsets.zero,
            onChanged: (i) => widget.onMatchTypeChanged(_types[i]),
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            value: widget.city,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
            decoration: const InputDecoration(
              labelText: 'City',
              isDense: true,
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
            items: [
              for (final c in kCities)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (c) {
              if (c != null) widget.onCityChanged(c);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  label: 'Date',
                  icon: Icons.event_outlined,
                  value: date == null ? 'Any date' : formatMatchDay(date),
                  onTap: _pickDate,
                  onClear:
                      date == null ? null : () => widget.onDateChanged(null),
                  clearTooltip: 'Clear date',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _PickerField(
                  label: 'Time',
                  icon: Icons.schedule_rounded,
                  value: time == null
                      ? 'Any time'
                      : 'Around ${formatClock(time.hour, time.minute)}',
                  onTap: _pickTime,
                  onClear:
                      time == null ? null : () => widget.onTimeChanged(null),
                  clearTooltip: 'Clear time',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Power range',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                rangeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.brand(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: range,
            min: 0,
            max: _maxPowerRange,
            divisions: 20,
            label: rangeLabel,
            activeColor: AppColors.brand(context),
            semanticFormatterCallback: (v) =>
                v.round() == 0 ? 'Any power' : 'Within ${v.round()} PWR',
            onChanged: (v) => setState(() => _dragRange = v),
            onChangeEnd: (v) {
              setState(() => _dragRange = null);
              widget.onPowerRangeChanged(v.round());
            },
          ),
          if (widget.isFiltered)
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Reset filters',
                variant: AppButtonVariant.ghost,
                icon: Icons.restart_alt_rounded,
                onPressed: widget.onReset,
              ),
            ),
        ],
      ),
    );
  }
}

/// A read-only field that opens a picker when tapped, with an optional clear
/// button once a value is set.
class _PickerField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String clearTooltip;

  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.onClear,
    required this.clearTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: Icon(icon),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  tooltip: clearTooltip,
                  icon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
                  onPressed: onClear,
                ),
        ),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
