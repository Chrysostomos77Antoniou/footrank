import 'package:flutter/material.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/recruitment_model.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/recruit/data/recruit_repository.dart';
import 'package:footrank/team/presentation/widgets/team_ui.dart';

typedef _RecruitData = ({
  List<RecruitmentModel> posts,
  Map<String, MyRequest> mine,
  String? city,
});

/// The Recruit tab: every team that is looking for players. Free agents and
/// players on other teams both see it; tap a team to ask to join.
class RecruitPage extends StatefulWidget {
  const RecruitPage({super.key});

  @override
  State<RecruitPage> createState() => _RecruitPageState();
}

class _RecruitPageState extends State<RecruitPage> with ThemeRepaintMixin {
  final _repo = RecruitRepository();
  late Future<_RecruitData> _future;
  bool _cityOnly = true;

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

  Future<_RecruitData> _load() async {
    final (posts, mine, profile) = await (
      _repo.fetchOpen(),
      _repo.fetchMyRequests(),
      // The list still works if the profile lookup fails.
      ProfileRepository().fetchMyProfile().catchError((_) => null),
    ).wait;
    return (posts: posts, mine: mine, city: profile?.city);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open(RecruitmentModel post, MyRequest? mine) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PostSheet(repo: _repo, post: post, mine: mine),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: FutureBuilder<_RecruitData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SkeletonList();
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: friendlyError(snapshot.error!),
                  onRetry: _reload,
                );
              }
              return _buildList(snapshot.data!);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(_RecruitData data) {
    final city = data.city?.trim();
    final hasCity = city != null && city.isNotEmpty;
    final posts = data.posts.where((p) {
      if (!_cityOnly || !hasCity) return true;
      return (p.team?.city ?? '').toLowerCase() == city.toLowerCase();
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Semantics(
            header: true,
            child: Text('Recruit', style: teamTitleStyle(context)),
          ),
          const SizedBox(height: 4),
          Text('Teams looking for players. Tap one to ask to join.',
              style: TextStyle(fontSize: 13, color: AppColors.muted(context))),
          if (hasCity) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(city),
                  selected: _cityOnly,
                  onSelected: (_) => setState(() => _cityOnly = true),
                ),
                ChoiceChip(
                  label: const Text('All cities'),
                  selected: !_cityOnly,
                  onSelected: (_) => setState(() => _cityOnly = false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (posts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyView(
                icon: Icons.person_search_rounded,
                title: 'No teams are recruiting right now',
                hint: 'Captains post here when their squad needs players.',
              ),
            )
          else
            ...posts.asMap().entries.map((e) {
              final post = e.value;
              final mine = data.mine[post.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  delay: AppMotion.staggerFor(e.key),
                  child: _PostCard(
                    post: post,
                    mine: mine,
                    onTap: () => _open(post, mine),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

String spotsText(RecruitmentModel p) =>
    p.spotsLeft == 1 ? 'Needs 1 player' : 'Needs ${p.spotsLeft} players';

class _PostCard extends StatelessWidget {
  final RecruitmentModel post;
  final MyRequest? mine;
  final VoidCallback onTap;
  const _PostCard({required this.post, required this.mine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final team = post.team;
    final muted = AppColors.muted(context);
    final req = mine;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TeamInitialsAvatar(
              name: team?.name ?? '?', imageUrl: team?.logoUrl, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team?.name ?? 'Team',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (team?.city != null) team!.city!,
                    if (team != null) 'PWR ${team.rating}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 6),
                Text(
                  [spotsText(post), if (post.position != null) post.position!]
                      .join(' · '),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand(context)),
                ),
              ],
            ),
          ),
          if (req != null)
            Chip(
              label: Text(req.status == 'pending' ? 'Requested' : 'Declined'),
              visualDensity: VisualDensity.compact,
            )
          else
            Icon(Icons.chevron_right, color: muted),
        ],
      ),
    );
  }
}

class _PostSheet extends StatefulWidget {
  final RecruitRepository repo;
  final RecruitmentModel post;
  final MyRequest? mine;
  const _PostSheet({required this.repo, required this.post, required this.mine});

  @override
  State<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends State<_PostSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSuccess(context, done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final team = post.team;
    final mine = widget.mine;
    final muted = AppColors.muted(context);

    Widget action;
    if (mine == null) {
      action = FilledButton(
        style: teamFilledStyle(),
        onPressed: _busy
            ? null
            : () => _run(() => widget.repo.requestJoin(post.id),
                'Request sent to ${team?.name ?? 'the team'}'),
        child: const Text('Ask to join'),
      );
    } else if (mine.status == 'pending') {
      action = OutlinedButton(
        style: teamOutlinedStyle(context),
        onPressed: _busy
            ? null
            : () => _run(
                () => widget.repo.cancelRequest(mine.id), 'Request cancelled'),
        child: const Text('Cancel request'),
      );
    } else {
      action = const Text('The captain declined your request.',
          textAlign: TextAlign.center);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TeamInitialsAvatar(
                    name: team?.name ?? '?', imageUrl: team?.logoUrl, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team?.name ?? 'Team',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      if (team != null)
                        Text(
                          [
                            if (team.city != null) team.city!,
                            'PWR ${team.rating}',
                            team.record,
                          ].join(' · '),
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              [spotsText(post), if (post.position != null) post.position!]
                  .join(' · '),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand(context)),
            ),
            if (post.note != null) ...[
              const SizedBox(height: 8),
              Text(post.note!, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: action),
          ],
        ),
      ),
    );
  }
}
