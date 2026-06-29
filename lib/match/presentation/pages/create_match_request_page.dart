import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/team/data/team_repository.dart';

class CreateMatchRequestPage extends StatefulWidget {
  /// The captain's team id (required to create a request).
  final String teamId;
  const CreateMatchRequestPage({super.key, required this.teamId});

  @override
  State<CreateMatchRequestPage> createState() => _CreateMatchRequestPageState();
}

class _CreateMatchRequestPageState extends State<CreateMatchRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = MatchRepository();
  final _teamRepo = TeamRepository();

  String? _city;
  DateTime? _date;
  TimeOfDay? _time;
  String _matchType = 'casual';
  bool _loading = false;

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
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
      // Default to the keyboard (type the time) — far clearer than the clock dial.
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Enter kick-off time',
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_city == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a city')),
      );
      return;
    }
    if (_date == null || _time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a date and time')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kick-off must be in the future')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _repo.createMatchRequest(
        teamId: widget.teamId,
        city: _city!,
        scheduledAt: scheduledAt,
        matchType: _matchType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Match request created')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _date == null
        ? 'Select date'
        : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}';
    final timeLabel = _time == null ? 'Select time' : _time!.format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Match')),
      body: AmbientBackground(
        child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _city,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  items: kCities
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _city = v),
                  validator: (v) => v == null ? 'City is required' : null,
                ),
                const SizedBox(height: 20),
                Text('Match Type',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'casual', label: Text('Casual')),
                    ButtonSegment(value: 'ranked', label: Text('Ranked')),
                  ],
                  selected: {_matchType},
                  onSelectionChanged: (s) =>
                      setState(() => _matchType = s.first),
                ),
                const SizedBox(height: 20),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.groups),
                  title: Text('Format'),
                  trailing: Text('5v5'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Match Request'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.iconAccent(context).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: AppColors.iconAccent(context)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'After creating, tap "Find Opponents" to match with a '
                          'nearby team at a similar time and rating.',
                          style: Theme.of(context).textTheme.bodySmall,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon, color: AppColors.iconAccent(context)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
