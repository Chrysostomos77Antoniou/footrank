import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/profile/presentation/widgets/profile_avatar.dart';

/// A match roster needs at least this many players.
const int kMinRoster = 5;

/// Checklist of a team's members used to choose who is playing a match.
/// Controlled: the parent owns [selected] and reacts to [onChanged].
/// With [readOnly] it just shows who is on the roster.
class RosterPicker extends StatelessWidget {
  final List<TeamMemberModel> members;
  final Set<String> selected;
  final ValueChanged<Set<String>>? onChanged;
  final bool readOnly;

  const RosterPicker({
    super.key,
    required this.members,
    required this.selected,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = selected.length;
    final enough = count >= kMinRoster;
    final allSelected = count == members.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$count of ${members.length} playing'
                '${enough ? '' : '  •  need at least $kMinRoster'}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enough ? null : AppColors.danger,
                ),
              ),
            ),
            if (!readOnly)
              TextButton(
                onPressed: () => onChanged?.call(
                  allSelected ? <String>{} : members.map((m) => m.userId).toSet(),
                ),
                child: Text(allSelected ? 'Clear all' : 'Select all'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final m in members)
          _row(context, m, selected.contains(m.userId)),
      ],
    );
  }

  Widget _row(BuildContext context, TeamMemberModel m, bool on) {
    final theme = Theme.of(context);
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ProfileAvatar(
        name: m.name,
        image: m.avatarUrl == null ? null : NetworkImage(m.avatarUrl!),
        size: 40,
        ring: 2,
        fontSize: 16,
      ),
      title: Text(m.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [m.roleLabel, if (m.position != null) m.position!].join(' · '),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: AppColors.muted(context)),
      ),
      trailing: readOnly
          ? (on
              ? Icon(Icons.check_circle, color: AppColors.brand(context))
              : null)
          : Checkbox(
              value: on,
              onChanged: (_) => _toggle(m.userId, on),
            ),
      onTap: readOnly ? null : () => _toggle(m.userId, on),
    );
    return tile;
  }

  void _toggle(String id, bool on) {
    final next = {...selected};
    on ? next.remove(id) : next.add(id);
    onChanged?.call(next);
  }
}

/// Bottom sheet to choose a roster (e.g. when proposing a match). Returns the
/// chosen user ids, or null if dismissed.
Future<List<String>?> showRosterSheet(
  BuildContext context, {
  required List<TeamMemberModel> members,
  Set<String>? initial,
  String title = 'Who is playing?',
  String confirmLabel = 'Confirm roster',
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var selected = initial ?? members.map((m) => m.userId).toSet();
      return StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'Pick the players who will play. You can change this until kick-off.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted(ctx)),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: RosterPicker(
                        members: members,
                        selected: selected,
                        onChanged: (s) => setState(() => selected = s),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: selected.length >= kMinRoster
                        ? () => Navigator.of(ctx).pop(selected.toList())
                        : null,
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
