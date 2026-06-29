import 'package:flutter/material.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:footrank/team/data/team_repository.dart';

/// Shown when the user is at the 3-team limit and wants to join another. Lists
/// their teams; leaving (or disbanding, for captains) one returns true so the
/// caller can retry the join/accept.
Future<bool> showLeaveTeamPicker(BuildContext context) async {
  final repo = TeamRepository();
  final teams = await repo.fetchMyTeams();
  if (!context.mounted) return false;
  final uid = SupabaseService.client.auth.currentUser?.id;

  return await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _LeaveSheet(repo: repo, teams: teams, uid: uid),
      ) ??
      false;
}

class _LeaveSheet extends StatefulWidget {
  final TeamRepository repo;
  final List<TeamModel> teams;
  final String? uid;
  const _LeaveSheet(
      {required this.repo, required this.teams, required this.uid});

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  String? _busyId;

  Future<void> _remove(TeamModel t, bool isCaptain) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isCaptain ? 'Disband ${t.name}?' : 'Leave ${t.name}?'),
        content: Text(isCaptain
            ? 'You are the captain, so leaving disbands ${t.name} for everyone. This cannot be undone.'
            : 'You will be removed from ${t.name}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(isCaptain ? 'Disband' : 'Leave')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = t.id);
    try {
      if (isCaptain) {
        await widget.repo.disbandTeam(t.id);
      } else {
        await widget.repo.leaveTeam(t.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text("You're already in 3 teams",
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Leave one to make room for the new team.'),
          ),
          ...widget.teams.map((t) {
            final isCaptain = t.captainId == widget.uid;
            return ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(t.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(isCaptain ? 'You are captain' : 'Member'),
              trailing: _busyId == t.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed:
                          _busyId == null ? () => _remove(t, isCaptain) : null,
                      child: Text(isCaptain ? 'Disband' : 'Leave'),
                    ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
