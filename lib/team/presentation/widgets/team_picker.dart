import 'package:flutter/material.dart';
import 'package:footrank/models/team_model.dart';

/// Bottom sheet to choose one of [teams]. Returns the chosen team, or null if
/// dismissed. Each row shows the team name (and city) clearly so the user can't
/// pick the wrong team by accident.
Future<TeamModel?> showTeamPicker(
  BuildContext context,
  List<TeamModel> teams, {
  String title = 'Choose a team',
}) {
  return showModalBottomSheet<TeamModel>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              title,
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ...teams.map(
            (t) => ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(t.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: t.city == null ? null : Text(t.city!),
              onTap: () => Navigator.of(ctx).pop(t),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Returns the only team without prompting; otherwise shows [showTeamPicker].
/// Returns null when [teams] is empty or the picker was dismissed.
Future<TeamModel?> chooseTeam(
  BuildContext context,
  List<TeamModel> teams, {
  String title = 'Choose a team',
}) async {
  if (teams.isEmpty) return null;
  if (teams.length == 1) return teams.first;
  return showTeamPicker(context, teams, title: title);
}
