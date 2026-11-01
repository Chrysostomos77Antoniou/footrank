import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/models/team_model.dart';

/// "Acting as  [Barcelona] [Elite]": which of your teams the screen is for.
///
/// Only worth showing to someone who is in more than one team, so the page
/// leaves it out otherwise. One quiet row -- the same pills as the other
/// filters -- instead of a label stacked above a row of chips.
class TeamSwitcher extends StatelessWidget {
  final List<TeamModel> teams;
  final String selectedId;
  final ValueChanged<TeamModel> onSelect;

  const TeamSwitcher({
    super.key,
    required this.teams,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final selected = teams.indexWhere((t) => t.id == selectedId);
    return Padding(
      padding: const EdgeInsets.only(left: AppSemantic.screenPadding),
      child: Row(
        children: [
          Text(
            'Acting as',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.muted(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: FilterPills(
              index: selected,
              items: [for (final t in teams) FilterPillItem(t.name)],
              onChanged: (i) => onSelect(teams[i]),
              padding: const EdgeInsets.only(right: AppSemantic.screenPadding),
            ),
          ),
        ],
      ),
    );
  }
}
