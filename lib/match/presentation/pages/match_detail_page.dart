import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_player_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';

class MatchDetailPage extends StatefulWidget {
  final String matchId;
  const MatchDetailPage({super.key, required this.matchId});

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  final _matchRepo = MatchRepository();
  final _teamRepo = TeamRepository();

  bool _loading = true;
  Object? _error;

  MatchModel? _match;
  bool _isCaptain = false;
  String? _myTeamId;
  String? _opponentTeamId;
  TeamModel? _homeTeam;
  TeamModel? _awayTeam;
  Map<String, MatchPlayerModel> _attendance = {};
  Map<String, String> _myBehavior = {}; // targetUserId -> 'good'|'bad'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final match = await _matchRepo.fetchMatchById(widget.matchId);
      final uid = SupabaseService.client.auth.currentUser?.id;
      final home = await _teamRepo.fetchById(match.homeTeamId);
      final away = await _teamRepo.fetchById(match.awayTeamId);

      bool isCaptain = false;
      String? myTeamId;
      String? opponentTeamId;
      if (uid == home.captainId) {
        isCaptain = true;
        myTeamId = home.id;
        opponentTeamId = away.id;
      } else if (uid == away.captainId) {
        isCaptain = true;
        myTeamId = away.id;
        opponentTeamId = home.id;
      }

      final attendance = await _matchRepo.fetchAttendance(match.id);
      final behavior = await _matchRepo.fetchMyBehavior(match.id);

      if (!mounted) return;
      setState(() {
        _match = match;
        _isCaptain = isCaptain;
        _myTeamId = myTeamId;
        _opponentTeamId = opponentTeamId;
        _homeTeam = home;
        _awayTeam = away;
        _attendance = attendance;
        _myBehavior = behavior;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _mark(TeamMemberModel player, bool attended) async {
    final match = _match!;
    try {
      await _matchRepo.markAttendance(
        matchId: match.id,
        userId: player.userId,
        teamId: player.teamId,
        attended: attended,
      );
      setState(() {
        _attendance[player.userId] = MatchPlayerModel(
          matchId: match.id,
          userId: player.userId,
          teamId: player.teamId,
          attended: attended,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rate(TeamMemberModel player, String rating, {String? reason}) async {
    final match = _match!;
    try {
      await _matchRepo.submitBehavior(
        matchId: match.id,
        targetUserId: player.userId,
        rating: rating,
        reason: reason,
      );
      setState(() => _myBehavior[player.userId] = rating);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _rateGood(TeamMemberModel player) => _rate(player, 'good');

  Future<void> _rateBad(TeamMemberModel player) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(playerName: player.name),
    );
    if (reason == null) return; // cancelled
    await _rate(player, 'bad', reason: reason);
  }

  Future<void> _submitScore() async {
    final match = _match!;
    final result = await showDialog<({int home, int away})>(
      context: context,
      builder: (ctx) => _ScoreDialog(
        homeName: match.homeTeamName ?? 'Home',
        awayName: match.awayTeamName ?? 'Away',
        initialHome: match.homeScore,
        initialAway: match.awayScore,
      ),
    );
    if (result == null) return;
    try {
      await _matchRepo.submitScore(
        matchId: match.id,
        homeScore: result.home,
        awayScore: result.away,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Score submitted. Awaiting confirmation.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _confirmScore() async {
    final match = _match!;
    try {
      final status = await _matchRepo.confirmScore(match.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'completed'
                ? 'Both confirmed — match completed!'
                : 'Score confirmed.'),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Widget _buildScoreSection() {
    final match = _match!;
    final myConfirmed =
        _myTeamId == match.homeTeamId ? match.homeConfirmed : match.awayConfirmed;
    final oppConfirmed =
        _myTeamId == match.homeTeamId ? match.awayConfirmed : match.homeConfirmed;

    final List<Widget> children = [
      Text('Final Score', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
    ];

    if (!match.hasScore) {
      children.add(const Text('No score submitted yet.'));
      children.add(const SizedBox(height: 12));
      children.add(FilledButton.icon(
        onPressed: _submitScore,
        icon: const Icon(Icons.scoreboard),
        label: const Text('Submit Score'),
      ));
    } else {
      children.add(Text(
        '${match.homeTeamName ?? 'Home'} ${match.homeScore} - '
        '${match.awayScore} ${match.awayTeamName ?? 'Away'}',
        style: Theme.of(context).textTheme.titleLarge,
      ));
      children.add(const SizedBox(height: 8));

      if (myConfirmed && !oppConfirmed) {
        children.add(const Text('Waiting for opponent to confirm…'));
        children.add(const SizedBox(height: 8));
        children.add(OutlinedButton(
          onPressed: _submitScore,
          child: const Text('Submit a different score'),
        ));
      } else if (!myConfirmed) {
        children.add(const Text('The opponent submitted this score.'));
        children.add(const SizedBox(height: 8));
        children.add(Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitScore,
                child: const Text('Disagree / Re-submit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _confirmScore,
                child: const Text('Confirm'),
              ),
            ),
          ],
        ));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    final match = _match!;
    final status = MatchStatus.fromString(match.status);
    final hasScore = match.homeScore != null && match.awayScore != null;
    final d = match.scheduledAt;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
        ' · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _TeamHeader(
                    name: match.homeTeamName ?? 'Home',
                    onTap: _homeTeam == null
                        ? null
                        : () => showTeamSheet(context, _homeTeam!),
                  ),
                ),
                Text(
                  hasScore ? '${match.homeScore} - ${match.awayScore}' : 'VS',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: _TeamHeader(
                    name: match.awayTeamName ?? 'Away',
                    onTap: _awayTeam == null
                        ? null
                        : () => showTeamSheet(context, _awayTeam!),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Time'),
                trailing: Text(when),
              ),
              ListTile(
                leading: const Icon(Icons.place),
                title: const Text('City'),
                trailing: Text(match.city),
              ),
              ListTile(
                leading: const Icon(Icons.flag),
                title: const Text('Status'),
                trailing: _StatusChip(status: status),
              ),
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Type / Format'),
                trailing: Text('${match.matchType} · ${match.format}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_isCaptain && status != MatchStatus.completed) _buildScoreSection(),
        const SizedBox(height: 16),
        if (_isCaptain)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              'As captain, mark the opponent players who attended.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _TeamRoster(
          title: match.homeTeamName ?? 'Home',
          teamId: match.homeTeamId,
          teamRepo: _teamRepo,
          attendance: _attendance,
          canMark: _isCaptain && _opponentTeamId == match.homeTeamId,
          onMark: _mark,
          canRate: _isCaptain &&
              _opponentTeamId == match.homeTeamId &&
              status == MatchStatus.completed,
          behavior: _myBehavior,
          onRateGood: _rateGood,
          onRateBad: _rateBad,
        ),
        const SizedBox(height: 16),
        _TeamRoster(
          title: match.awayTeamName ?? 'Away',
          teamId: match.awayTeamId,
          teamRepo: _teamRepo,
          attendance: _attendance,
          canMark: _isCaptain && _opponentTeamId == match.awayTeamId,
          onMark: _mark,
          canRate: _isCaptain &&
              _opponentTeamId == match.awayTeamId &&
              status == MatchStatus.completed,
          behavior: _myBehavior,
          onRateGood: _rateGood,
          onRateBad: _rateBad,
        ),
      ],
    );
  }
}

class _TeamHeader extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  const _TeamHeader({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 2.5),
            ),
            child: GradientAvatar(name: name, radius: 28),
          ),
          const SizedBox(height: 8),
          Text(name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall),
          if (onTap != null)
            Text('Tap to view',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.brand(context),
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MatchStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.isCompleted
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status.label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _TeamRoster extends StatelessWidget {
  final String title;
  final String teamId;
  final TeamRepository teamRepo;
  final Map<String, MatchPlayerModel> attendance;
  final bool canMark;
  final void Function(TeamMemberModel player, bool attended) onMark;
  final bool canRate;
  final Map<String, String> behavior;
  final void Function(TeamMemberModel player) onRateGood;
  final void Function(TeamMemberModel player) onRateBad;

  const _TeamRoster({
    required this.title,
    required this.teamId,
    required this.teamRepo,
    required this.attendance,
    required this.canMark,
    required this.onMark,
    this.canRate = false,
    this.behavior = const {},
    required this.onRateGood,
    required this.onRateBad,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title — Players',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<TeamMemberModel>>(
          future: teamRepo.fetchMembers(teamId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final members = snapshot.data ?? [];
            if (members.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No players listed'),
              );
            }
            return Column(
              children: members.map((m) {
                final att = attendance[m.userId]?.attended;
                final Widget trailing;
                if (canRate) {
                  trailing = _BehaviorControl(
                    rating: behavior[m.userId],
                    onGood: () => onRateGood(m),
                    onBad: () => onRateBad(m),
                  );
                } else if (canMark) {
                  trailing = _AttendanceToggle(
                    attended: att,
                    onPresent: () => onMark(m, true),
                    onAbsent: () => onMark(m, false),
                  );
                } else {
                  trailing = _AttendanceBadge(attended: att);
                }
                return Card(
                  child: ListTile(
                    dense: true,
                    onTap: () => showPlayerSheetById(context, m.userId),
                    leading: GradientAvatar(name: m.name, radius: 18),
                    title: Text(m.name),
                    subtitle: Text(
                      [if (m.position != null) m.position, 'ELO ${m.elo}']
                          .join(' · '),
                    ),
                    trailing: trailing,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _AttendanceToggle extends StatelessWidget {
  final bool? attended;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;

  const _AttendanceToggle({
    required this.attended,
    required this.onPresent,
    required this.onAbsent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.check_circle,
            color: attended == true ? Colors.green : Colors.grey,
          ),
          tooltip: 'Attended',
          onPressed: onPresent,
        ),
        IconButton(
          icon: Icon(
            Icons.cancel,
            color: attended == false ? Colors.red : Colors.grey,
          ),
          tooltip: 'Did not attend',
          onPressed: onAbsent,
        ),
      ],
    );
  }
}

class _AttendanceBadge extends StatelessWidget {
  final bool? attended;
  const _AttendanceBadge({required this.attended});

  @override
  Widget build(BuildContext context) {
    if (attended == null) return const SizedBox.shrink();
    return Icon(
      attended! ? Icons.check_circle : Icons.cancel,
      color: attended! ? Colors.green : Colors.red,
    );
  }
}

class _BehaviorControl extends StatelessWidget {
  final String? rating; // null = not yet rated
  final VoidCallback onGood;
  final VoidCallback onBad;

  const _BehaviorControl({
    required this.rating,
    required this.onGood,
    required this.onBad,
  });

  @override
  Widget build(BuildContext context) {
    if (rating != null) {
      // Already rated — show the chosen verdict, locked.
      final good = rating == 'good';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          good ? Icons.thumb_up : Icons.thumb_down,
          color: good ? Colors.green : Colors.red,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.thumb_up_outlined),
          tooltip: 'Good behavior',
          onPressed: onGood,
        ),
        IconButton(
          icon: const Icon(Icons.thumb_down_outlined),
          tooltip: 'Bad behavior',
          onPressed: onBad,
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String playerName;
  const _ReasonDialog({required this.playerName});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.playerName}'),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'What went wrong?',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _ctrl.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a reason')),
              );
              return;
            }
            Navigator.pop(context, reason);
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _ScoreDialog extends StatefulWidget {
  final String homeName;
  final String awayName;
  final int? initialHome;
  final int? initialAway;

  const _ScoreDialog({
    required this.homeName,
    required this.awayName,
    this.initialHome,
    this.initialAway,
  });

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  late final _homeCtrl =
      TextEditingController(text: widget.initialHome?.toString() ?? '');
  late final _awayCtrl =
      TextEditingController(text: widget.initialAway?.toString() ?? '');

  @override
  void dispose() {
    _homeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final h = int.tryParse(_homeCtrl.text.trim());
    final a = int.tryParse(_awayCtrl.text.trim());
    if (h == null || a == null || h < 0 || a < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid scores')),
      );
      return;
    }
    Navigator.pop(context, (home: h, away: a));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Final Score'),
      content: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.homeName, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextField(
                  controller: _homeCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('-', style: TextStyle(fontSize: 24)),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.awayName, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextField(
                  controller: _awayCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}
