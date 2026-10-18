import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/models/match_model.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "16 Oct 2026" in the admin's local time.
String adminDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// Small uppercase heading used to split a detail dialog into sections.
class AdminDetailSection extends StatelessWidget {
  final String title;
  const AdminDetailSection(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).hintColor,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// One "label ........ value" line. The value can be selected and copied
/// (handy for ids).
class AdminInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const AdminInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: hint, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A match in a history list. When [myTeamIds] is given the row shows the
/// result (W / L / D) from that side's point of view.
class AdminMatchTile extends StatelessWidget {
  final MatchModel match;
  final Set<String> myTeamIds;
  const AdminMatchTile({
    super.key,
    required this.match,
    this.myTeamIds = const {},
  });

  String? get _result {
    if (match.status != 'completed' || !match.hasScore) return null;
    final home = match.homeScore!;
    final away = match.awayScore!;
    if (home == away) return 'D';
    final homeMine = myTeamIds.contains(match.homeTeamId);
    final awayMine = myTeamIds.contains(match.awayTeamId);
    if (!homeMine && !awayMine) return null;
    final homeWon = home > away;
    return (homeWon && homeMine) || (!homeWon && awayMine) ? 'W' : 'L';
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final result = _result;
    final resultColor = switch (result) {
      'W' => Colors.green,
      'L' => Colors.redAccent,
      _ => hint,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              result ?? '·',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: resultColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${match.homeTeamName ?? '?'} vs ${match.awayTeamName ?? '?'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    adminDate(match.scheduledAt),
                    match.city,
                    match.status,
                    if (match.paymentStatus != 'unpaid')
                      'fee ${match.paymentStatus}',
                    if (match.scoreDisputed) 'disputed',
                  ].join(' · '),
                  style: TextStyle(color: hint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            match.hasScore ? '${match.homeScore}-${match.awayScore}' : '–',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
