import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/court_model.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final List<String> _selectedCourtIds = []; // ordered, up to 3
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
        _selectedCourtIds.clear();
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

  void _toggleCourt(String courtId) {
    setState(() {
      if (_selectedCourtIds.contains(courtId)) {
        _selectedCourtIds.remove(courtId);
      } else if (_selectedCourtIds.length < 3) {
        _selectedCourtIds.add(courtId);
      }
    });
  }

  Future<void> _openMaps(CourtModel c) async {
    final query = [c.name, if (c.address != null) c.address, c.city].join(', ');
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a city')));
      return;
    }
    if (_date == null || _time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a date and time')),
      );
      return;
    }
    if (_selectedCourtIds.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick & rank 3 courts, in order of preference'),
        ),
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
        courtIds: _selectedCourtIds,
        format: _format,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Match request created')));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildCourtPicker() {
    if (_courtsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_courts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.iconAccent(context).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _city == null
              ? 'Select a city to see courts.'
              : 'No courts listed yet for $_city.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 380,
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
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: active
                    ? AppColors.brand(context)
                    : AppColors.iconAccent(context).withValues(alpha: 0.25),
              ),
            );
          }),
        ),
        if (_selectedCourtIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildSelectedSummary(),
        ],
      ],
    );
  }

  Widget _buildCourtCard(CourtModel c) {
    final rank = _selectedCourtIds.indexOf(c.id);
    final picked = rank != -1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        color: picked ? AppColors.brand(context).withValues(alpha: 0.08) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: picked
              ? BorderSide(color: AppColors.brand(context), width: 2)
              : BorderSide.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Capped square: sized off the card's own width but never taller
            // than 240 — a true square that still leaves guaranteed room for
            // the name/address/button below inside the fixed carousel height.
            LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth < 240
                    ? constraints.maxWidth
                    : 240.0;
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: InkWell(
                      onTap: () => _toggleCourt(c.id),
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
                            child: _RoundIconButton(
                              icon: Icons.map_outlined,
                              tooltip: 'View on map',
                              onPressed: () => _openMaps(c),
                            ),
                          ),
                          if (picked)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: AppColors.brand(context),
                                child: Text(
                                  '${rank + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (c.address != null)
                    Text(
                      c.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: picked
                        ? OutlinedButton.icon(
                            onPressed: () => _toggleCourt(c.id),
                            icon: const Icon(Icons.close, size: 18),
                            label: Text('Remove (#${rank + 1} choice)'),
                          )
                        : FilledButton.icon(
                            onPressed: _selectedCourtIds.length < 3
                                ? () => _toggleCourt(c.id)
                                : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                              'Add as #${_selectedCourtIds.length + 1} choice',
                            ),
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
    color: AppColors.iconAccent(context).withValues(alpha: 0.08),
    child: Icon(
      Icons.sports_soccer,
      size: 56,
      color: AppColors.iconAccent(context).withValues(alpha: 0.5),
    ),
  );

  /// Compact recap of the current ranking — the carousel only shows one court
  /// at a time, so without this the earlier picks scroll out of view.
  Widget _buildSelectedSummary() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _selectedCourtIds.asMap().entries.map((entry) {
        final i = entry.key;
        final court = _courts.firstWhere((c) => c.id == entry.value);
        return InputChip(
          avatar: CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.brand(context),
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          label: Text(court.name, overflow: TextOverflow.ellipsis),
          onDeleted: () => _toggleCourt(court.id),
        );
      }).toList(),
    );
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
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _city = v);
                      _loadCourts();
                    },
                    validator: (v) => v == null ? 'City is required' : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Pick & Rank 3 Courts',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap in order of preference. We\'ll match you with an opponent who wants the same courts, starting from your #1 choice.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _buildCourtPicker(),
                  const SizedBox(height: 20),
                  Text(
                    'Match Type',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
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
                      color: AppColors.iconAccent(
                        context,
                      ).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppColors.iconAccent(context),
                        ),
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

/// A small circular icon button that sits legibly on top of a photo.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
