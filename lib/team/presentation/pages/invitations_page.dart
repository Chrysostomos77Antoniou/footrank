import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/invitation_model.dart';
import 'package:footrank/rankings/presentation/widgets/profile_sheets.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/leave_team_picker.dart';
import 'package:footrank/team/presentation/widgets/team_ui.dart';
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
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const TeamPageHeader(title: 'Team Invitations'),
              const SizedBox(height: 4),
              Expanded(
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
                              hint:
                                  'Team captains can invite you from Free Agents.',
                            ),
                          ],
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            20, AppSpacing.sm, 20, AppSpacing.xl),
                        itemCount: invites.length,
                        itemBuilder: (context, i) {
                          final inv = invites[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FadeSlideIn(
                              delay: AppMotion.staggerFor(i),
                              child: _InvitationCard(
                                inv: inv,
                                onView: () => _viewTeam(inv),
                                onDecline: () => _decline(inv),
                                onAccept: () => _accept(inv),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final InvitationModel inv;
  final VoidCallback onView;
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  const _InvitationCard({
    required this.inv,
    required this.onView,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.muted(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'View ${inv.teamName}',
            excludeSemantics: true,
            child: InkWell(
              onTap: onView,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    TeamInitialsAvatar(
                        name: inv.teamName, imageUrl: inv.teamLogo, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inv.teamName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.16)),
                          if (inv.teamCity != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(inv.teamCity!,
                                  style: TextStyle(fontSize: 12, color: muted)),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Bound each button with Expanded: the themed buttons use an
          // infinite min width, which would overflow an unbounded Row.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: teamOutlinedStyle(context),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: teamFilledStyle(),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
