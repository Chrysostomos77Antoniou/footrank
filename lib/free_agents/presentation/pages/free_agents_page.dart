import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/free_agents/data/free_agent_repository.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';

const _positions = ['Goalkeeper', 'Defender', 'Midfielder', 'Forward'];

class FreeAgentsPage extends StatefulWidget {
  const FreeAgentsPage({super.key});

  @override
  State<FreeAgentsPage> createState() => _FreeAgentsPageState();
}

class _FreeAgentsPageState extends State<FreeAgentsPage> {
  final _repo = FreeAgentRepository();
  final _teamRepo = TeamRepository();
  FreeAgentFilter _filter = const FreeAgentFilter();
  late Future<List<UserModel>> _future;

  TeamModel? _myTeam;
  final Set<String> _invitedIds = {};

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
    setState(() => _future = _repo.fetchFreeAgents(_filter));
    _loadCaptainContext();
  }

  Future<void> _loadCaptainContext() async {
    final team = await _teamRepo.fetchMyTeam();
    final uid = SupabaseService.client.auth.currentUser?.id;
    if (team == null || team.captainId != uid) return;
    final invited = await _teamRepo.fetchPendingInviteeIds(team.id);
    if (!mounted) return;
    setState(() {
      _myTeam = team;
      _invitedIds
        ..clear()
        ..addAll(invited);
    });
  }

  Future<void> _invite(UserModel agent) async {
    final team = _myTeam;
    if (team == null) return;
    try {
      await _teamRepo.invitePlayer(teamId: team.id, userId: agent.id);
      if (!mounted) return;
      setState(() => _invitedIds.add(agent.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${agent.name}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
      appBar: AppBar(title: const Text('Free Agents')),
      body: AmbientBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _FilterBar(filter: _filter, onChanged: _applyFilter),
            ),
            Expanded(
              child: FutureBuilder<List<UserModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final agents = snapshot.data ?? [];
                  if (agents.isEmpty) {
                    return const Center(
                      child: Text('No free agents match these filters'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: agents.length,
                    itemBuilder: (context, i) {
                      final a = agents[i];
                      return FadeSlideIn(
                        delay: Duration(milliseconds: 30 * i),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AgentCard(
                            agent: a,
                            canInvite: _myTeam != null,
                            invited: _invitedIds.contains(a.id),
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
              GradientAvatar(
                  name: agent.name, imageUrl: agent.avatarUrl, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '@${agent.username} · ${agent.position ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              GradientPill(text: 'ELO ${agent.elo}', icon: Icons.bolt),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Chip(icon: Icons.shield_outlined, text: '${agent.reliability}%'),
              const SizedBox(width: 8),
              _Chip(icon: Icons.handshake_outlined, text: agent.behaviorLabel),
              const Spacer(),
              if (canInvite)
                invited
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Invited',
                            style: TextStyle(fontStyle: FontStyle.italic)),
                      )
                    : FilledButton.icon(
                        onPressed: onInvite,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: filter.position,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Position',
              isDense: true,
              prefixIcon: Icon(Icons.sports_handball_outlined),
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
    return Row(
      children: [
        SizedBox(
            width: 70,
            child:
                Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            activeColor: AppColors.brand(context),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
            width: 44,
            child: Text(display,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium)),
      ],
    );
  }
}
