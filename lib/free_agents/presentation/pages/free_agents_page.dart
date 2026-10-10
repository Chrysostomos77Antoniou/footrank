import 'package:footrank/core/widgets/back_chip.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/free_agents/data/free_agent_repository.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/rankings/presentation/widgets/rank_row_parts.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_picker.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/theme_controller.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class FreeAgentsPage extends StatefulWidget {
  const FreeAgentsPage({super.key});

  @override
  State<FreeAgentsPage> createState() => _FreeAgentsPageState();
}

class _FreeAgentsPageState extends State<FreeAgentsPage>
    with ThemeRepaintMixin {
  final _repo = FreeAgentRepository();
  final _teamRepo = TeamRepository();
  FreeAgentFilter _filter = const FreeAgentFilter();
  late Future<List<UserModel>> _future;

  // Teams the viewer captains, and per team the users with a pending invite.
  List<TeamModel> _captainTeams = [];
  final Map<String, Set<String>> _invitedByTeam = {};

  /// True once [agentId] has a pending invite from every team the viewer
  /// captains (so there is nobody left to invite them to).
  bool _fullyInvited(String agentId) =>
      _captainTeams.isNotEmpty &&
      _captainTeams
          .every((t) => _invitedByTeam[t.id]?.contains(agentId) ?? false);

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchFreeAgents(_filter);
    _loadCaptainContext();
    appRefresh.addListener(_refresh);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _repo.fetchFreeAgents(_filter);
    });
    _loadCaptainContext();
  }

  Future<void> _loadCaptainContext() async {
    final captainTeams = await _teamRepo.fetchMyCaptainTeams();
    if (!mounted) return;
    if (captainTeams.isEmpty) {
      setState(() {
        _captainTeams = [];
        _invitedByTeam.clear();
      });
      return;
    }
    final pending = await Future.wait(
        captainTeams.map((t) => _teamRepo.fetchPendingInviteeIds(t.id)));
    if (!mounted) return;
    setState(() {
      _captainTeams = captainTeams;
      _invitedByTeam
        ..clear()
        ..addEntries([
          for (var i = 0; i < captainTeams.length; i++)
            MapEntry(captainTeams[i].id, pending[i]),
        ]);
    });
  }

  Future<void> _invite(UserModel agent) async {
    // With one captained team there is nothing to choose. With several, always
    // show the list; teams that already have a pending invite for this player
    // are shown greyed out and cannot be tapped.
    final invitedTeamIds = {
      for (final t in _captainTeams)
        if (_invitedByTeam[t.id]?.contains(agent.id) ?? false) t.id,
    };
    final team = _captainTeams.length == 1
        ? _captainTeams.first
        : await showTeamPicker(context, _captainTeams,
            title: 'Invite ${agent.name} to…',
            disabledTeamIds: invitedTeamIds);
    if (!mounted || team == null) return;
    try {
      await _teamRepo.invitePlayer(teamId: team.id, userId: agent.id);
      if (!mounted) return;
      setState(() => _invitedByTeam
          .putIfAbsent(team.id, () => <String>{})
          .add(agent.id));
      showSuccess(context, 'Invitation sent to ${agent.name} for ${team.name}');
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  void _applyFilter(FreeAgentFilter filter) {
    setState(() {
      _filter = filter;
      _future = _repo.fetchFreeAgents(_filter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        leadingWidth: kBackChipLeadingWidth,
        titleSpacing: 0,
        leading: Navigator.of(context).canPop() ? const BackChip() : null,
        title: Text(
          'Free Agents',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.26,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: _FilterBar(filter: _filter, onChanged: _applyFilter),
              ),
              Expanded(
                child: FutureBuilder<List<UserModel>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LoadingView();
                    }
                    if (snapshot.hasError) {
                      return ErrorView(
                          onRetry: () => _applyFilter(_filter));
                    }
                    final agents = snapshot.data ?? [];
                    if (agents.isEmpty) {
                      return const EmptyView(
                        icon: Icons.person_search_outlined,
                        title: 'No free agents found',
                        hint: 'Try clearing the filters, or check back later.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 100),
                      itemCount: agents.length,
                      itemBuilder: (context, i) {
                        final a = agents[i];
                        return FadeSlideIn(
                          delay: AppMotion.staggerFor(i),
                          animateOnceId: a.id,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AgentCard(
                              agent: a,
                              canInvite: _captainTeams.isNotEmpty,
                              invited: _fullyInvited(a.id),
                              onInvite: () => _invite(a),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final UserModel agent;
  final bool canInvite;
  final bool invited;
  final VoidCallback onInvite;

  const _AgentCard({
    required this.agent,
    required this.canInvite,
    required this.invited,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => showPlayerSheet(context, agent),
      child: Column(
        children: [
          Row(
            children: [
              GreenAvatar(
                  name: agent.name, imageUrl: agent.avatarUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.15)),
                    const SizedBox(height: AppSemantic.labelGap),
                    Text(
                      '@${agent.username} · ${agent.position ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12, color: AppColors.muted(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PwrScoreBadge(value: agent.elo, height: 44, minWidth: 55),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatPill(
                  icon: Icons.shield_outlined, text: '${agent.reliability}%'),
              const SizedBox(width: 8),
              Flexible(
                child: _StatPill(
                    icon: Icons.handshake_outlined, text: agent.behaviorLabel),
              ),
              const Spacer(),
              if (canInvite)
                invited
                    ? Container(
                        height: 44,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Invited',
                            style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: AppColors.muted(context))),
                      )
                    : FilledButton.icon(
                        onPressed: onInvite,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          backgroundColor: AppColors.action,
                          foregroundColor: AppColors.onAction(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppSemantic.controlRadius),
                          ),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Invite'),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small stat chip (reliability, behaviour): chip fill, accent text in light.
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFFD5DCE3) : AppColors.limeDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.chip(context),
        borderRadius: BorderRadius.circular(AppSemantic.statusPillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final FreeAgentFilter filter;
  final ValueChanged<FreeAgentFilter> onChanged;

  const _FilterBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POSITION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.muted(context),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: filter.position,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted(context)),
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Any position',
              fillColor: isDark ? AppColors.darkBg : AppColors.lightCard,
              constraints: const BoxConstraints(minHeight: 52),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              prefixIcon: Icon(Icons.person_outline_rounded,
                  size: 20, color: AppColors.onChip(context)),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Any position'),
              ),
              ..._positions.map((p) => DropdownMenuItem(
                  value: p, child: Text(p))),
            ],
            onChanged: (v) => onChanged(
              filter.copyWith(position: v, clearPosition: v == null),
            ),
          ),
          const SizedBox(height: 4),
          _SliderRow(
            label: 'Min ELO',
            value: filter.minElo.toDouble(),
            min: 0,
            max: 2500,
            divisions: 25,
            display: filter.minElo == 0 ? 'Any' : '${filter.minElo}',
            onChanged: (v) => onChanged(filter.copyWith(minElo: v.round())),
          ),
          _SliderRow(
            label: 'Min Rel.',
            value: filter.minReliability.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            display:
                filter.minReliability == 0 ? 'Any' : '${filter.minReliability}%',
            onChanged: (v) =>
                onChanged(filter.copyWith(minReliability: v.round())),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.brand(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.muted(context),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: accent,
                inactiveTrackColor: isDark
                    ? const Color(0xFF2A343F)
                    : const Color(0xFFD8E0DB),
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.14),
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10, elevation: 2),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 20),
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                valueIndicatorColor: accent,
                valueIndicatorTextStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onAction(context),
                ),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: display,
                semanticFormatterCallback: (_) => '$label $display',
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
