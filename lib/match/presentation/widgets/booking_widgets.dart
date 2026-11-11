import 'dart:async';

import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/maps_launcher.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/booking_repository.dart';
import 'package:footrank/match/presentation/widgets/venue_map_picker.dart';
import 'package:footrank/models/booking_models.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:go_router/go_router.dart';

const kBookingAmber = Color(0xFFF5A524);

/// "1h 20m", "25m", "under a minute".
String bookingCountdown(Duration d) {
  if (d.isNegative || d.inSeconds < 60) return 'under a minute';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String _hhmm(DateTime t) {
  final d = t.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _dayTime(DateTime t) {
  final d = t.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · ${_hhmm(d)}';
}

/// Why a match was cancelled, in plain words (null if not a booking reason).
String? bookingCancelText(String? reason) => switch (reason) {
      'court_not_booked' => 'Cancelled: the court wasn\'t confirmed as booked.',
      'venue_declined_3' => 'Cancelled: no court was agreed after 3 declined suggestions.',
      'venue_unresolved' => 'Cancelled: the court change wasn\'t answered in time.',
      _ => null,
    };

/// Amber "Not booked yet" / green "Booked" / red "Cancelled" strip.
class BookingStatusStrip extends StatelessWidget {
  final MatchModel match;
  final bool compact;
  const BookingStatusStrip({super.key, required this.match, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = match.status == 'cancelled'
        ? (AppColors.danger, Icons.cancel_outlined, 'Cancelled')
        : match.venueChangeOpen
            ? (kBookingAmber, Icons.swap_horiz_rounded, 'Venue being changed')
            : match.isBooked
                ? (AppColors.success, Icons.check_circle_outline, 'Booked ✓')
                : (kBookingAmber, Icons.schedule_rounded, 'Not booked yet');
    final booker = match.bookerTeamName;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: compact ? 4 : AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          if (booker != null && match.status != 'cancelled') ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                match.isBooked ? 'by $booker' : '$booker books',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted(context)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The booking section of the match page: who books, the buttons, the open
/// court change and the timeline.
class BookingPanel extends StatefulWidget {
  final MatchModel match;

  /// The signed-in user's team in this match, and whether they captain it.
  final String? myTeamId;
  final bool isCaptain;
  final VoidCallback onChanged;

  const BookingPanel({
    super.key,
    required this.match,
    required this.myTeamId,
    required this.isCaptain,
    required this.onChanged,
  });

  @override
  State<BookingPanel> createState() => _BookingPanelState();
}

class _BookingPanelState extends State<BookingPanel> {
  final _repo = BookingRepository();
  VenueSuggestionModel? _pending;
  List<MatchEventModel> _events = const [];
  int _mySuggestions = 0;
  int? _bookerReliability;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BookingPanel old) {
    super.didUpdateWidget(old);
    if (old.match != widget.match) _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final m = widget.match;
    try {
      final results = await Future.wait([
        _repo.fetchPendingSuggestion(m.id),
        _repo.fetchEvents(m.id),
        _repo.fetchReliability(m.bookerTeamId),
        if (widget.myTeamId != null)
          _repo.countMySuggestions(m.id, widget.myTeamId!),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0] as VenueSuggestionModel?;
        _events = results[1] as List<MatchEventModel>;
        _bookerReliability = results[2] as int?;
        if (results.length > 3) _mySuggestions = results[3] as int;
      });
    } catch (_) {
      // The panel still works from the match row alone.
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccess(context, done);
      triggerAppRefresh();
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _teamName(String? id) {
    final m = widget.match;
    if (id == null) return null;
    if (id == m.homeTeamId) return m.homeTeamName;
    if (id == m.awayTeamId) return m.awayTeamName;
    return null;
  }

  Future<void> _confirmBooked() async {
    final ok = await confirmBookedDialog(context, widget.match);
    if (ok != true) return;
    await _run(() => _repo.confirmBooked(widget.match.id),
        'Court booked. The other captain was notified.');
  }

  Future<void> _courtFull() async {
    final pick = await venuePicker(context, city: widget.match.city);
    if (pick == null || !mounted) return;
    await _run(
      () => _repo.suggestVenue(
          matchId: widget.match.id,
          venueText: pick.name,
          location: pick.location),
      'Court suggested. Waiting for the other captain.',
    );
  }

  Future<void> _counter(VenueSuggestionModel s) async {
    final pick = await venuePicker(context, city: widget.match.city);
    if (pick == null || !mounted) return;
    await _run(
      () => _repo.counterVenue(
          suggestionId: s.id, venueText: pick.name, location: pick.location),
      'Your court was sent to the other captain.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final now = DateTime.now();
    final iAmBooker = widget.isCaptain && widget.myTeamId == m.bookerTeamId;
    final active = m.status == 'confirmed';
    final deadline = m.bookingDeadlineAt;
    final cancelText = bookingCancelText(m.cancelReason);
    final pending = _pending;
    final iSuggested = pending != null && pending.suggestedByTeamId == widget.myTeamId;
    final canSuggest = active &&
        widget.isCaptain &&
        pending == null &&
        !m.venueChangeOpen &&
        _mySuggestions < 3 &&
        now.isBefore(m.scheduledAt.subtract(const Duration(minutes: 20)));

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Court booking',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          BookingStatusStrip(match: m),
          if (_bookerReliability != null && m.bookerTeamName != null) ...[
            const SizedBox(height: 6),
            Text(
              '${m.bookerTeamName} court reliability: $_bookerReliability/100',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: reliabilityColor(_bookerReliability!)),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (cancelText != null)
            Text(cancelText, style: TextStyle(color: AppColors.dangerText(context)))
          else if (active && m.needsBooking && deadline != null)
            Text(
              iAmBooker
                  ? 'You book the court. Tap "I booked it" by ${_hhmm(deadline)} '
                      '(${bookingCountdown(deadline.difference(now))} left) or the match cancels.'
                  : '${m.bookerTeamName ?? 'The other team'} is booking the court '
                      '(deadline ${_hhmm(deadline)}).',
              style: TextStyle(color: muted),
            )
          else if (active && m.isBooked)
            Text(
              '${m.bookerTeamName ?? 'The Booker'} booked the court'
              '${m.bookedAt == null ? '' : ' at ${_hhmm(m.bookedAt!)}'}.',
              style: TextStyle(color: muted),
            ),
          if (active && m.needsBooking && !m.venueChangeOpen) ...[
            const SizedBox(height: AppSpacing.sm),
            if (iAmBooker)
              FilledButton.icon(
                onPressed: _busy ? null : _confirmBooked,
                icon: const Icon(Icons.check_rounded),
                label: const Text('I booked it'),
              )
            else if (widget.isCaptain)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => _repo.claimBooking(m.id),
                        'You book the court now.'),
                icon: const Icon(Icons.front_hand_outlined),
                label: const Text('I\'ll book it'),
              ),
          ],
          if (pending != null && active) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: kBookingAmber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    iSuggested
                        ? 'You suggested ${pending.venueText}. Waiting for the other captain.'
                        : '${_teamName(pending.suggestedByTeamId) ?? 'The other team'} '
                            'suggests ${pending.venueText}.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (pending.location != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => openVenueInMaps(
                            name: pending.venueText,
                            city: m.city,
                            location: pending.location),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('See it in Maps'),
                      ),
                    ),
                  if (!iSuggested && widget.isCaptain) ...[
                    Text(
                      'If you accept, they book the new court.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _repo.respondVenue(pending.id, accept: true),
                                    'New court accepted.'),
                            child: const Text('Accept'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _repo.respondVenue(pending.id, accept: false),
                                    'Suggestion declined.'),
                            child: const Text('Decline'),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _counter(pending),
                      child: const Text('Suggest another court'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (canSuggest) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              onPressed: _busy ? null : _courtFull,
              icon: const Icon(Icons.block_rounded),
              label: Text('Court full? Suggest another (${3 - _mySuggestions} left)'),
            ),
          ],
          if (_events.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Timeline',
                style: theme.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 4),
            for (final e in _events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(_hhmm(e.createdAt),
                          style: TextStyle(color: muted, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(e.describe(teamName: _teamName),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Only tap this when the court is really booked."
Future<bool?> confirmBookedDialog(BuildContext context, MatchModel m) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Is the court booked?'),
        content: Text(
            'Confirm only once ${m.venueText ?? 'the court'} is booked for '
            '${_dayTime(m.scheduledAt)}. The other captain will be told it\'s booked.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, it\'s booked')),
        ],
      ),
    );

/// Full-screen card the Booker has to tap through. Returns true when they
/// confirmed the booking, false for "Not yet".
Future<bool> showBookerGate(BuildContext context, MatchModel m) async {
  final repo = BookingRepository();
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (ctx, _, __) => PopScope(
      canPop: false,
      child: _BookerGate(match: m, repo: repo),
    ),
  );
  return result ?? false;
}

class _BookerGate extends StatefulWidget {
  final MatchModel match;
  final BookingRepository repo;
  const _BookerGate({required this.match, required this.repo});

  @override
  State<_BookerGate> createState() => _BookerGateState();
}

class _BookerGateState extends State<_BookerGate> {
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _booked() async {
    final ok = await confirmBookedDialog(context, widget.match);
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.confirmBooked(widget.match.id);
      if (!mounted) return;
      triggerAppRefresh();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final theme = Theme.of(context);
    final deadline = m.bookingDeadlineAt;
    final left = deadline?.difference(DateTime.now());
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.sports_soccer, size: 56, color: AppColors.brand(context)),
              const SizedBox(height: AppSpacing.md),
              Text('You book the court',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'FootRank is not affiliated with any court. Book it yourself, '
                'then tap "I booked it".',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted(context)),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.venueText ?? 'Court',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${_dayTime(m.scheduledAt)} · ${m.city}'),
                    if ((m.homeTeamName ?? '').isNotEmpty)
                      Text('${m.homeTeamName} vs ${m.awayTeamName ?? ''}',
                          style: TextStyle(color: AppColors.muted(context))),
                    if (left != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Book within ${bookingCountdown(left)} or the match cancels.',
                        style: const TextStyle(
                            color: kBookingAmber, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: (m.venueText ?? '').isEmpty
                    ? null
                    : () => openVenueInMaps(
                        name: m.venueText!, city: m.city, location: m.venueLocation),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Maps'),
              ),
              const SizedBox(height: AppSpacing.xs),
              FilledButton.icon(
                onPressed: _busy ? null : _booked,
                icon: const Icon(Icons.check_rounded),
                label: const Text('I booked it'),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Not yet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home banner for a Booker with a court still to book, with a live
/// countdown. Also shows the full-screen Booker card when the app opens or
/// comes back to the foreground.
class PendingBookingBanner extends StatefulWidget {
  const PendingBookingBanner({super.key});

  @override
  State<PendingBookingBanner> createState() => _PendingBookingBannerState();
}

class _PendingBookingBannerState extends State<PendingBookingBanner>
    with WidgetsBindingObserver {
  final _repo = BookingRepository();
  List<MatchModel> _matches = const [];
  Timer? _tick;
  bool _gateOpen = false;

  /// When each match's Booker card was last shown (this app session).
  static final Map<String, DateTime> _gateShown = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appRefresh.addListener(_load);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load(showGate: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRefresh.removeListener(_load);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(showGate: true);
  }

  Future<void> _load({bool showGate = false}) async {
    try {
      final list = await _repo.fetchMyUnbookedMatches();
      if (!mounted) return;
      setState(() => _matches = list);
      if (showGate) await _maybeShowGate();
    } catch (_) {
      // Non-fatal: the match page still shows the booking.
    }
  }

  Future<void> _maybeShowGate() async {
    if (_gateOpen || _matches.isEmpty) return;
    final m = _matches.first;
    final last = _gateShown[m.id];
    // Once per app open: again only after 30 minutes away.
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _gateShown[m.id] = DateTime.now();
    _gateOpen = true;
    await showBookerGate(context, m);
    _gateOpen = false;
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_matches.isEmpty) return const SizedBox.shrink();
    final m = _matches.first;
    final deadline = m.bookingDeadlineAt;
    final left = deadline?.difference(DateTime.now());
    final extra = _matches.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        tint: kBookingAmber,
        onTap: () => context.push(AppRoutes.matchDetail, extra: m.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: kBookingAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.venueChangeOpen
                        ? 'Court change open for ${m.venueText ?? 'your match'}'
                        : 'Book ${m.venueText ?? 'the court'}'
                            '${left == null ? '' : ' within ${bookingCountdown(left)}'}'
                            ' or the match cancels',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${_dayTime(m.scheduledAt)} · ${m.city}',
                style: TextStyle(color: AppColors.muted(context))),
            if (!m.venueChangeOpen) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () async {
                    final ok = await confirmBookedDialog(context, m);
                    if (ok != true) return;
                    try {
                      await _repo.confirmBooked(m.id);
                      triggerAppRefresh();
                      if (context.mounted) {
                        showSuccess(context, 'Court booked. The other captain was notified.');
                      }
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  child: const Text('I booked it'),
                ),
              ),
            ],
            if (extra > 0)
              Text(
                extra == 1 ? '1 more court to book' : '$extra more courts to book',
                style: TextStyle(color: AppColors.muted(context)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox + sentence, e.g. "If this match is confirmed, you book the court."
class BookingAckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;
  const BookingAckRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Colour for a reliability score: green 80+, amber 50-79, red below.
Color reliabilityColor(int score) => score >= 80
    ? AppColors.success
    : score >= 50
        ? kBookingAmber
        : AppColors.danger;

/// Team page card: "Court reliability 90/100 · 1 missed booking".
class ReliabilityCard extends StatelessWidget {
  final int score;
  final int missed;
  const ReliabilityCard({super.key, required this.score, required this.missed});

  @override
  Widget build(BuildContext context) {
    final color = reliabilityColor(score);
    final muted = AppColors.muted(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Court reliability',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  missed == 0
                      ? 'No missed bookings'
                      : missed == 1
                          ? '1 match cancelled: court not booked'
                          : '$missed matches cancelled: court not booked',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score.clamp(0, 100) / 100,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('$score',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text('/100', style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}
