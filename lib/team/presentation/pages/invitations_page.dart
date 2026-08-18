import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/invitation_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/leave_team_picker.dart';
import 'package:footrank/core/widgets/feedback.dart';

class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key});

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  final _repo = TeamRepository();
  late Future<List<InvitationModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _repo.fetchMyInvitations();
    });
  }

  Future<void> _accept(InvitationModel inv) async {
    try {
      await _repo.acceptInvitation(inv);
      if (mounted) {
        showSuccess(context, 'You joined ${inv.teamName}');
      }
      _reload();
    } on TeamLimitException {
      // Already in 3 teams — let them leave one, then retry the accept.
      if (!mounted) return;
      final freed = await showLeaveTeamPicker(context);
      if (freed && mounted) await _accept(inv);
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _viewTeam(InvitationModel inv) async {
    try {
      final team = await _repo.fetchById(inv.teamId);
      if (mounted) showTeamSheet(context, team);
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  Future<void> _decline(InvitationModel inv) async {
    try {
      await _repo.declineInvitation(inv);
      _reload();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team Invitations')),
      body: AmbientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<InvitationModel>>(
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
                final invites = snapshot.data ?? [];
                if (invites.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyView(
                        icon: Icons.mail_outline,
                        title: 'No pending invitations',
                        hint: 'Team captains can invite you from Free Agents.',
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
                  itemCount: invites.length,
                  itemBuilder: (context, i) {
                    final inv = invites[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FadeSlideIn(
                        delay: AppMotion.staggerFor(i),
                        child: GlassCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => _viewTeam(inv),
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  children: [
                                    GradientAvatar(
                                      name: inv.teamName,
                                      imageUrl: inv.teamLogo,
                                      radius: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(inv.teamName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800)),
                                          if (inv.teamCity != null)
                                            Text(inv.teamCity!,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.4)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              // Bound each button with Expanded: the app's button
                              // theme uses Size.fromHeight (infinite min width), which
                              // in an unbounded Row pushes the filled "Accept" button
                              // off-screen. Expanded gives them equal bounded widths.
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _decline(inv),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _accept(inv),
                                      child: const Text('Accept'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
