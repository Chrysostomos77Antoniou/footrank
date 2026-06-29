import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/join_request_model.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> with ThemeRepaintMixin {
  final _repo = TeamRepository();
  late Future<List<TeamModel>> _teamsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    appRefresh.addListener(_reload);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _teamsFuture = _repo.fetchMyTeams();
    });
  }

  Future<void> _openCreateTeam() async {
    final created = await context.push<bool>(AppRoutes.createTeam);
    if (created == true) _reload();
  }

  Future<void> _openJoinTeam() async {
    await context.push<bool>(AppRoutes.joinTeam);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: FutureBuilder<List<TeamModel>>(
            future: _teamsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList();
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final teams = snapshot.data ?? [];
              if (teams.isEmpty) {
                return _NoTeamView(
                  onCreate: _openCreateTeam,
                  onJoin: _openJoinTeam,
                );
              }
              return _buildTeamsList(teams);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTeamsList(List<TeamModel> teams) {
    final uid = SupabaseService.client.auth.currentUser?.id;
    final canAdd = teams.length < TeamRepository.maxTeamsPerUser;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const GradientText('My Teams',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${teams.length}/${TeamRepository.maxTeamsPerUser}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...teams.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FadeSlideIn(
                    delay: Duration(milliseconds: 60 * e.key),
                    child: _TeamListCard(
                      team: e.value,
                      isCaptain: e.value.captainId == uid,
                      onTap: () async {
                        await context.push(AppRoutes.teamDetail, extra: e.value);
                        _reload();
                      },
                    ),
                  ),
                ),
              ),
          if (canAdd) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openCreateTeam,
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openJoinTeam,
                    icon: const Icon(Icons.login),
                    label: const Text('Join'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A summary card for one of the user's teams in the Team tab list.
class _TeamListCard extends StatelessWidget {
  final TeamModel team;
  final bool isCaptain;
  final VoidCallback onTap;
  const _TeamListCard(
      {required this.team, required this.isCaptain, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.iconAccent(context);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: team.logoUrl != null
                ? CachedNetworkImage(
                    imageUrl: team.logoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Icon(Icons.shield_outlined, color: accent),
                  )
                : Icon(Icons.shield_outlined, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (team.city != null && team.city!.isNotEmpty) team.city!,
                    isCaptain ? 'Captain' : 'Player',
                  ].join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (isCaptain)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: CaptainArmband(label: 'C'),
            ),
          Icon(Icons.arrow_forward_ios,
              size: 16,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

/// Full detail for one team (reuses [_TeamView]); pushed from the Team tab list.
class TeamDetailPage extends StatefulWidget {
  final TeamModel team;
  const TeamDetailPage({super.key, required this.team});

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  final _repo = TeamRepository();
  late TeamModel _team = widget.team;

  Future<void> _refresh() async {
    final teams = await _repo.fetchMyTeams();
    if (!mounted) return;
    final remaining = teams.where((t) => t.id == _team.id).toList();
    if (remaining.isEmpty) {
      // The user left or disbanded this team — return to the list.
      Navigator.of(context).pop();
    } else {
      setState(() => _team = remaining.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_team.name)),
      body: AmbientBackground(
        child: SafeArea(
          child: _TeamView(team: _team, repo: _repo, onChanged: _refresh),
        ),
      ),
    );
  }
}

class _NoTeamView extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  const _NoTeamView({required this.onCreate, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FadeSlideIn(
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined,
                    size: 56, color: AppColors.iconAccent(context)),
                const SizedBox(height: 12),
                const GradientText(
                  'No team yet',
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create your own squad or join one with an invite code.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _GradientButton(
                  label: 'Create Team',
                  icon: Icons.add,
                  onTap: onCreate,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.login),
                  label: const Text('Join with Invite Code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamView extends StatelessWidget {
  final TeamModel team;
  final TeamRepository repo;
  final VoidCallback onChanged;

  const _TeamView({
    required this.team,
    required this.repo,
    required this.onChanged,
  });

  bool get _isCaptain =>
      SupabaseService.client.auth.currentUser?.id == team.captainId;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          FadeSlideIn(
            child: _TeamHeaderCard(
              team: team,
              onEdit: _isCaptain
                  ? () async {
                      final updated = await context.push<bool>(
                          AppRoutes.editTeam,
                          extra: team);
                      if (updated == true) onChanged();
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    leading: Icon(Icons.star_rounded,
                        color: AppColors.iconAccent(context)),
                    value: '${team.rating}',
                    label: 'Pitch Power',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniStat(
                    leading: Icon(Icons.emoji_events_outlined,
                        color: AppColors.iconAccent(context)),
                    value: '${team.wins}-${team.losses}'
                        '${team.draws > 0 ? '-${team.draws}' : ''}',
                    label: 'W-L${team.draws > 0 ? '-D' : ''}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniStat(
                    leading: _isCaptain
                        ? const CaptainArmband(label: 'C')
                        : Icon(Icons.person, color: AppColors.iconAccent(context)),
                    value: _isCaptain ? 'Captain' : 'Player',
                    label: 'Your Role',
                  ),
                ),
              ],
            ),
          ),
          if (_isCaptain && team.inviteCode != null) ...[
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: _InviteCodeCard(code: team.inviteCode!),
            ),
          ],
          if (_isCaptain)
            _PendingRequests(team: team, repo: repo, onChanged: onChanged),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Squad',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          _MemberList(
            teamId: team.id,
            repo: repo,
            isCaptain: _isCaptain,
            onChanged: onChanged,
          ),
          const SizedBox(height: 24),
          _LeaveDisbandButton(
            team: team,
            repo: repo,
            isCaptain: _isCaptain,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LeaveDisbandButton extends StatelessWidget {
  final TeamModel team;
  final TeamRepository repo;
  final bool isCaptain;
  final VoidCallback onChanged;
  const _LeaveDisbandButton({
    required this.team,
    required this.repo,
    required this.isCaptain,
    required this.onChanged,
  });

  Future<void> _run(BuildContext context) async {
    final title = isCaptain ? 'Disband team?' : 'Leave team?';
    final body = isCaptain
        ? 'This deletes ${team.name} and removes all its members, requests and '
            'matches. This cannot be undone.'
        : 'You will leave ${team.name}. You can join another team afterwards.';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isCaptain ? 'Disband' : 'Leave'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (isCaptain) {
        await repo.disbandTeam(team.id);
      } else {
        await repo.leaveTeam(team.id);
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _run(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
      ),
      icon: Icon(isCaptain ? Icons.delete_outline : Icons.logout),
      label: Text(isCaptain ? 'Disband team' : 'Leave team'),
    );
  }
}

class _TeamHeaderCard extends StatelessWidget {
  final TeamModel team;
  final VoidCallback? onEdit;
  const _TeamHeaderCard({required this.team, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 2.5),
            ),
            child: team.logoUrl != null
                ? CircleAvatar(
                    radius: 32, backgroundImage: CachedNetworkImageProvider(team.logoUrl!))
                : GradientAvatar(name: team.name, radius: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                if (team.city != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place_outlined,
                          size: 15, color: AppColors.iconAccent(context)),
                      const SizedBox(width: 4),
                      Text(team.city!,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Team',
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final Widget leading;
  final String value;
  final String label;
  const _MiniStat(
      {required this.leading, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        children: [
          SizedBox(height: 26, child: Center(child: leading)),
          const SizedBox(height: 8),
          GradientText(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  final String code;
  const _InviteCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Icon(Icons.vpn_key_outlined,
              size: 26, color: AppColors.iconAccent(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite Code',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(code,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3)),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GradientButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 54,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brand(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.onBrand(context)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: AppColors.onBrand(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _PendingRequests extends StatefulWidget {
  final TeamModel team;
  final TeamRepository repo;
  final VoidCallback onChanged;

  const _PendingRequests({
    required this.team,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<_PendingRequests> createState() => _PendingRequestsState();
}

class _PendingRequestsState extends State<_PendingRequests> {
  late Future<List<JoinRequestModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.fetchPendingRequests(widget.team.id);
  }

  void _reload() {
    setState(() {
      _future = widget.repo.fetchPendingRequests(widget.team.id);
    });
  }

  Future<void> _approve(JoinRequestModel r) async {
    try {
      await widget.repo.approveRequest(r);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${r.name} added to team')));
      }
      _reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _reject(JoinRequestModel r) async {
    try {
      await widget.repo.rejectRequest(r);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<JoinRequestModel>>(
      future: _future,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Join Requests',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            ...requests.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        GradientAvatar(name: r.name, radius: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                [
                                  if (r.position != null) r.position,
                                  'PWR ${r.elo}'
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: AppColors.success),
                          onPressed: () => _approve(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel,
                              color: AppColors.danger),
                          onPressed: () => _reject(r),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}

class _MemberList extends StatefulWidget {
  final String teamId;
  final TeamRepository repo;
  final bool isCaptain;
  final VoidCallback onChanged;

  const _MemberList({
    required this.teamId,
    required this.repo,
    required this.isCaptain,
    required this.onChanged,
  });

  @override
  State<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<_MemberList> {
  late Future<List<TeamMemberModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.fetchMembers(widget.teamId);
  }

  void _reload() {
    setState(() {
      _future = widget.repo.fetchMembers(widget.teamId);
    });
  }

  Future<void> _setRole(TeamMemberModel m, String role) async {
    try {
      await widget.repo
          .updateMemberRole(teamId: m.teamId, userId: m.userId, role: role);
      _reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _remove(TeamMemberModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text('Remove ${m.name} from the team?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.removeMember(teamId: m.teamId, userId: m.userId);
      _reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Color _roleColor(BuildContext context, TeamMemberModel m) => m.isCaptain
      ? AppColors.gold
      : (m.isViceCaptain ? AppColors.brand(context) : Colors.transparent);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeamMemberModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final members = snapshot.data ?? [];
        if (members.isEmpty) return const Text('No players yet');
        return Column(
          children: members.map((m) {
            final showActions = widget.isCaptain && !m.isCaptain;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    GradientAvatar(name: m.name, radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(m.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              if (m.isCaptain || m.isViceCaptain) ...[
                                const SizedBox(width: 8),
                                CaptainArmband(
                                    label: m.isCaptain ? 'C' : 'VC'),
                              ],
                            ],
                          ),
                          Text(
                            [
                              if (m.position != null) m.position,
                              'PWR ${m.elo}',
                              '${m.reliability}%'
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!showActions)
                      _RoleChip(member: m, color: _roleColor(context, m))
                    else
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) {
                          switch (v) {
                            case 'make_vice':
                              _setRole(m, 'vice_captain');
                            case 'make_player':
                              _setRole(m, 'player');
                            case 'remove':
                              _remove(m);
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (!m.isViceCaptain)
                            const PopupMenuItem(
                                value: 'make_vice',
                                child: Text('Make Vice Captain')),
                          if (m.isViceCaptain)
                            const PopupMenuItem(
                                value: 'make_player',
                                child: Text('Demote to Player')),
                          const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from Team')),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _RoleChip extends StatelessWidget {
  final TeamMemberModel member;
  final Color color;
  const _RoleChip({required this.member, required this.color});

  @override
  Widget build(BuildContext context) {
    if (member.role == 'player') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(member.roleLabel,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
