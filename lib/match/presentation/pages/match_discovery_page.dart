import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/level_badge.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/court_repository.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MatchDiscoveryPage extends StatefulWidget {
  final String teamId;
  const MatchDiscoveryPage({super.key, required this.teamId});

  @override
  State<MatchDiscoveryPage> createState() => _MatchDiscoveryPageState();
}

class _MatchDiscoveryPageState extends State<MatchDiscoveryPage> {
  final _repo = MatchRepository();
  final _courtRepo = CourtRepository();
  final _teamRepo = TeamRepository();

  late Future<List<MatchRequestModel>> _myRequestsFuture;
  MatchRequestModel? _reference;
  Future<List<MatchRequestModel>>? _opponentsFuture;

  // Dismissed rejections expire after 24h so stale ones don't accumulate.
  static const Duration _dismissTtl = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _myRequestsFuture = _repo.fetchSearchingRequests(widget.teamId);
    _loadDismissed();
  }

  // Locally rejected opponent request ids -> timestamp (ms) when dismissed.
  final Map<String, int> _dismissed = {};

  String get _dismissKey => 'match_discovery_dismissed_${widget.teamId}';

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dismissKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = _dismissTtl.inMilliseconds;
      final loaded = <String, int>{};
      decoded.forEach((key, value) {
        if (value is int && (now - value) < cutoff) {
          loaded[key.toString()] = value;
        }
      });
      if (!mounted) return;
      setState(() {
        _dismissed
          ..clear()
          ..addAll(loaded);
      });
      // Persist back the pruned set so stale entries don't linger.
      if (loaded.length != decoded.length) {
        await _saveDismissed();
      }
    } catch (_) {
      // Best-effort persistence; ignore corrupt/unavailable storage.
    }
  }

  Future<void> _saveDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissKey, jsonEncode(_dismissed));
    } catch (_) {
      // Best-effort persistence; ignore storage errors.
    }
  }

  void _markDismissed(String id) {
    _dismissed[id] = DateTime.now().millisecondsSinceEpoch;
    _saveDismissed();
  }

  Future<List<MatchRequestModel>> _findOpponentsFor(
      MatchRequestModel ref) async {
    final myCourtIds = await _courtRepo.fetchPicksForRequest(ref.id);
    return _repo.findOpponents(
      myTeamId: widget.teamId,
      myTeamRating: ref.teamRating ?? 1500,
      city: ref.city,
      scheduledAt: ref.scheduledAt,
      myCourtIds: myCourtIds,
    );
  }

  void _selectReference(MatchRequestModel ref) {
    setState(() {
      _reference = ref;
      _opponentsFuture = _findOpponentsFor(ref);
    });
  }

  Future<void> _accept(MatchRequestModel opponent) async {
    final ref = _reference;
    if (ref == null) return;

    // Matches are 5-a-side -- fail fast with a clear message instead of
    // letting the request hit the server's "at least 5 players" check.
    final members = await _teamRepo.fetchMembers(widget.teamId);
    if (!mounted) return;
    if (members.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your team needs at least 5 players before you can accept a '
            'match (currently ${members.length}).',
          ),
        ),
      );
      return;
    }

    try {
      await _repo.acceptMatchRequest(
        requestId: opponent.id,
        awayTeamId: widget.teamId,
        myRequestId: ref.id,
      );
      if (!mounted) return;
      setState(() => _markDismissed(opponent.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Match requested against ${opponent.teamName}. '
                'Waiting for their captain to confirm.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _reject(MatchRequestModel opponent) {
    setState(() => _markDismissed(opponent.id));
  }

  Future<void> _inviteRival() async {
    final ref = _reference;
    var msg = "Hey! We're looking for a match";
    if (ref != null) {
      final d = ref.scheduledAt.toLocal();
      final date = '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')} at '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
      msg += ' in ${ref.city} on $date';
    }
    msg += ". Got a team? Let's set one up on FootRank!";
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  /// Opponents are sorted by court compatibility first, then time, then
  /// rating — this surfaces WHY one's ranked above another (score is
  /// combined 1st=3pts/2nd=2pts/3rd=1pt from both sides; max 6 = both
  /// picked the same court as their #1 choice).
  String? _courtBadge(int? score) {
    if (score == null || score == 0) return null;
    if (score == 6) return '🎯 Matches your #1 court choice exactly';
    if (score >= 3) return '✓ Court preferences overlap';
    return '· Shares a lower-ranked court pick';
  }

  String _label(MatchRequestModel r) {
    final d = r.scheduledAt.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${r.city} · $date $time · ${r.matchType}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Opponents')),
      body: AmbientBackground(
        child: SafeArea(
          child: FutureBuilder<List<MatchRequestModel>>(
            future: _myRequestsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorView(message: friendlyError(snapshot.error!));
              }
              final myRequests = snapshot.data ?? [];
              if (myRequests.isEmpty) {
                return const EmptyView(
                  icon: Icons.sports_soccer_outlined,
                  title: 'No open match requests',
                  hint: 'Create an open match request first, then come back '
                      'to find opponents.',
                );
              }

              // Default to first reference once loaded.
              _reference ??= myRequests.first;
              _opponentsFuture ??= _findOpponentsFor(_reference!);

              return Column(
                children: [
                  FadeSlideIn(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<MatchRequestModel>(
                        value: _reference,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Your match request',
                          isDense: true,
                        ),
                        items: myRequests
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(_label(r),
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (r) {
                          if (r != null) _selectReference(r);
                        },
                      ),
                    ),
                  ),
                  Expanded(child: _buildOpponents()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOpponents() {
    return FutureBuilder<List<MatchRequestModel>>(
      future: _opponentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return ErrorView(message: friendlyError(snapshot.error!));
        }
        final opponents = (snapshot.data ?? [])
            .where((o) => !_dismissed.containsKey(o.id))
            .toList();
        if (opponents.isEmpty) {
          final ref = _reference;
          final rd = ref?.scheduledAt.toLocal();
          final rating = ref?.teamRating;
          final band = MatchRepository.defaultEloThreshold;
          final mins = MatchRepository.defaultWithinMinutes;
          final onSurface = Theme.of(context).colorScheme.onSurface;
          final refLine = rd == null
              ? ''
              : 'Looking for: ${ref!.city} on '
                  '${rd.day.toString().padLeft(2, '0')}/'
                  '${rd.month.toString().padLeft(2, '0')}/'
                  '${rd.year} around '
                  '${rd.hour.toString().padLeft(2, '0')}:'
                  '${rd.minute.toString().padLeft(2, '0')}.';
          // Show the captain WHY nothing matched, so they can self-diagnose
          // (visibility of system status) instead of hitting a dead screen.
          final ratingLine = rating == null
              ? 'Your team has no rating yet — matching uses the starting 1500 '
                  '(±$band points).'
              : 'Your rating: $rating   ·   matching window ±$band points.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FadeSlideIn(
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brand(context).withValues(alpha: 0.10),
                        ),
                        child: Icon(Icons.search_off,
                            size: 36, color: AppColors.brand(context)),
                      ),
                      const SizedBox(height: 16),
                      Text('No matching opponents found',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        'Opponents must be in the same city, on the same date '
                        '(±$mins min), and within ±$band rating points.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted(context)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(ratingLine,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                      if (refLine.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(refLine,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.muted(context))),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Invite a rival team'),
                          onPressed: _inviteRival,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: opponents.length,
          itemBuilder: (context, i) {
            final o = opponents[i];
            final d = o.scheduledAt.toLocal();
            final time =
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            return FadeSlideIn(
              delay: Duration(milliseconds: 50 * i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GradientAvatar(name: o.teamName ?? '?', radius: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.teamName ?? 'Unknown team',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('${o.city} · $time · ${o.matchType}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          LevelBadge(value: o.teamRating ?? 0, size: 36),
                        ],
                      ),
                    if (_courtBadge(o.courtCompatibilityScore) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _courtBadge(o.courtCompatibilityScore)!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    const SizedBox(height: 10),
                    // Expanded bounds the buttons; the themed FilledButton uses
                    // an infinite min width that would otherwise overflow the Row.
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _reject(o),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _accept(o),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
