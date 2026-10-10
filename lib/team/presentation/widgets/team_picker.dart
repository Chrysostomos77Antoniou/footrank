import 'package:flutter/material.dart';
import 'package:footrank/match/presentation/widgets/match_team_avatar.dart';
import 'package:footrank/models/team_model.dart';

/// Bottom sheet to choose one of [teams]. Returns the chosen team, or null if
/// dismissed. Each row shows the team crest (logo, or a monogram when it has
/// none) plus the name and city so the user can't pick the wrong team by
/// accident.
Future<TeamModel?> showTeamPicker(
  BuildContext context,
  List<TeamModel> teams, {
  String title = 'Choose a team',
  Set<String> disabledTeamIds = const {},
  String disabledLabel = 'Already invited',
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
          ...teams.map((t) {
            final disabled = disabledTeamIds.contains(t.id);
            final grey = Theme.of(ctx).disabledColor;
            final sub = disabled
                ? disabledLabel
                : t.city;
            return ListTile(
              enabled: !disabled,
              leading: Opacity(
                opacity: disabled ? 0.4 : 1,
                child: MatchTeamAvatar(
                    name: t.name, imageUrl: t.logoUrl, radius: 22),
              ),
              title: Text(t.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: disabled ? grey : null)),
              subtitle: sub == null
                  ? null
                  : Text(sub, style: TextStyle(color: disabled ? grey : null)),
              onTap: disabled ? null : () => Navigator.of(ctx).pop(t),
            );
          }),
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
