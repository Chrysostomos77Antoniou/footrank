import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/recruitment_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/recruit/data/recruit_repository.dart';
import 'package:footrank/recruit/presentation/pages/recruit_page.dart'
    show spotsText;
import 'package:footrank/team/presentation/widgets/team_ui.dart';

/// Captain-only card on the team page: post "we need N players" to the
/// Recruit tab, or see / close the open post.
class TeamRecruitCard extends StatefulWidget {
  final TeamModel team;
  final RecruitRepository repo;
  final VoidCallback onChanged;
  const TeamRecruitCard(
      {super.key,
      required this.team,
      required this.repo,
      required this.onChanged});

  @override
  State<TeamRecruitCard> createState() => _TeamRecruitCardState();
}

class _TeamRecruitCardState extends State<TeamRecruitCard> {
  late Future<RecruitmentModel?> _future = _load();

  Future<RecruitmentModel?> _load() => widget.repo
      .fetchOpenForTeam(widget.team.id)
      // The card just shows the "Find players" button if the lookup fails.
      .catchError((_) => null);

  // The team page reloads after approving a request, which may have filled the
  // post, so refetch whenever the parent rebuilds us.
  @override
  void didUpdateWidget(TeamRecruitCard old) {
    super.didUpdateWidget(old);
    _future = _load();
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CreateSheet(team: widget.team, repo: widget.repo),
    );
    if (created == true) {
      setState(() {
        _future = _load();
      });
      widget.onChanged();
    }
  }

  Future<void> _close(RecruitmentModel post) async {
    final ok = await confirmDestructive(
      context,
      title: 'Close this request?',
      body: 'Players waiting for an answer will be declined.',
      confirmLabel: 'Close',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repo.close(post.id);
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RecruitmentModel?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final post = snapshot.data;
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: post == null
                ? Row(
                    children: [
                      Icon(Icons.person_search_rounded,
                          color: AppColors.brand(context)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Need more players?',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      FilledButton(
                        style: teamFilledStyle(height: 40),
                        onPressed: _create,
                        child: const Text('Find players'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.campaign_rounded,
                          color: AppColors.brand(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recruiting now',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted(context))),
                            Text(
                              [
                                spotsText(post),
                                if (post.position != null) post.position!
                              ].join(' · '),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                          onPressed: () => _close(post),
                          child: const Text('Close')),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CreateSheet extends StatefulWidget {
  final TeamModel team;
  final RecruitRepository repo;
  const _CreateSheet({required this.team, required this.repo});

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _note = TextEditingController();
  int _spots = 1;
  String? _position;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      await widget.repo.create(
        teamId: widget.team.id,
        spots: _spots,
        position: _position,
        note: _note.text,
      );
      if (!mounted) return;
      showSuccess(context, 'Posted to the Recruit tab');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Find players',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Your team shows up in the Recruit tab for 14 days.',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.muted(context))),
              const SizedBox(height: 16),
              const TeamFieldLabel('How many players?'),
              Wrap(
                spacing: 8,
                children: [
                  for (var n = 1; n <= 5; n++)
                    ChoiceChip(
                      key: Key('spots-$n'),
                      label: Text('$n'),
                      selected: _spots == n,
                      onSelected: (_) => setState(() => _spots = n),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const TeamFieldLabel('Position (optional)'),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in RecruitRepository.positions)
                    ChoiceChip(
                      label: Text(p),
                      selected: _position == p,
                      onSelected: (on) =>
                          setState(() => _position = on ? p : null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('recruit-note'),
                controller: _note,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Tuesdays 9pm, friendly level',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('recruit-post'),
                  style: teamFilledStyle(),
                  onPressed: _busy ? null : _post,
                  child: const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
