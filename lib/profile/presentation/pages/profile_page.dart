import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/emojis.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/team/data/team_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _profileRepo = ProfileRepository();
  final _authRepo = AuthRepository();
  final _teamRepo = TeamRepository();
  final _matchRepo = MatchRepository();
  late Future<UserModel?> _profileFuture;
  late Future<({String? teamId, List<MatchModel> matches})> _historyFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _profileRepo.fetchMyProfile();
    _historyFuture = _loadHistory();
    appRefresh.addListener(_refresh);
  }

  Future<({String? teamId, List<MatchModel> matches})> _loadHistory() async {
    final team = await _teamRepo.fetchMyTeam();
    if (team == null) return (teamId: null, matches: <MatchModel>[]);
    final all = await _matchRepo.fetchTeamMatches(team.id);
    final completed =
        all.where((m) => m.status == 'completed').take(10).toList();
    return (teamId: team.id, matches: completed);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _historyFuture = _loadHistory();
      _profileFuture = _profileRepo.fetchMyProfile();
    });
  }

  Future<void> _signOut() async {
    await _authRepo.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  Future<void> _openPrivacy() async {
    final uri = Uri.parse(
        'https://chrysostomos77antoniou.github.io/footrank/privacy.html');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the privacy policy')),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This permanently deletes your account, profile, and any team you '
            'captain. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _authRepo.deleteAccount();
      if (mounted) context.go(AppRoutes.login);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openEdit(UserModel user) async {
    final updated = await context.push<bool>(AppRoutes.editProfile, extra: user);
    if (updated == true) {
      setState(() => _profileFuture = _profileRepo.fetchMyProfile());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: FutureBuilder<UserModel?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final user = snapshot.data;
            if (user == null) {
              return const Center(child: Text('No profile found'));
            }
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedBuilder(
                        animation: themeController,
                        builder: (context, _) {
                          final mode = themeController.mode;
                          final (icon, label) = switch (mode) {
                            ThemeMode.system => (Icons.brightness_auto, 'Auto'),
                            ThemeMode.light => (Icons.light_mode, 'Light'),
                            ThemeMode.dark => (Icons.dark_mode, 'Dark'),
                          };
                          return TextButton.icon(
                            onPressed: themeController.toggle,
                            icon: Icon(icon, size: 20),
                            label: Text(label),
                          );
                        },
                      ),
                      IconButton(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        tooltip: 'Sign Out',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    child: _ProfileHero(
                      user: user,
                      onEdit: () => _openEdit(user),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: Row(
                      children: [
                        _StatCard(
                          label: 'Pitch Power',
                          value: '${user.elo}',
                          icon: Icons.trending_up,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Matches',
                          value: '${user.matchesPlayed}',
                          icon: Icons.sports_soccer,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 200),
                    child: Row(
                      children: [
                        _StatCard(
                          label: 'Reliability',
                          value: '${user.reliability}%',
                          icon: Icons.verified_user_outlined,
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Behavior',
                          value: user.behaviorLabel,
                          icon: Icons.handshake_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: _MatchHistory(future: _historyFuture),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 260),
                    child: GlassCard(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.privacy_tip_outlined,
                                color: AppColors.iconAccent(context)),
                            title: const Text('Privacy Policy'),
                            trailing: const Icon(Icons.open_in_new, size: 18),
                            onTap: _openPrivacy,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.delete_forever,
                                color: AppColors.danger),
                            title: const Text('Delete account',
                                style: TextStyle(color: AppColors.danger)),
                            onTap: _deleteAccount,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MatchHistory extends StatelessWidget {
  final Future<({String? teamId, List<MatchModel> matches})> future;
  const _MatchHistory({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String? teamId, List<MatchModel> matches})>(
      future: future,
      builder: (context, snap) {
        final data = snap.data;
        final matches = data?.matches ?? [];
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (data?.teamId == null || matches.isEmpty) {
          return const SizedBox.shrink();
        }
        final myTeamId = data!.teamId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Match History',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            GlassCard(
              child: Column(
                children: [
                  for (var i = 0; i < matches.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _historyRow(context, matches[i], myTeamId),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _historyRow(BuildContext context, MatchModel m, String? myTeamId) {
    final iAmHome = m.homeTeamId == myTeamId;
    final myScore = iAmHome ? m.homeScore : m.awayScore;
    final oppScore = iAmHome ? m.awayScore : m.homeScore;
    final oppName = iAmHome ? m.awayTeamName : m.homeTeamName;
    String result = 'DRAW';
    Color color = AppColors.silver;
    if (myScore != null && oppScore != null) {
      if (myScore > oppScore) {
        result = 'WON';
        color = AppColors.success;
      } else if (myScore < oppScore) {
        result = 'LOST';
        color = AppColors.danger;
      }
    }
    final d = m.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text('vs ${oppName ?? 'Opponent'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${m.homeScore ?? '-'} - ${m.awayScore ?? '-'} · $when'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(result,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  const _ProfileHero({required this.user, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Profile',
              visualDensity: VisualDensity.compact,
            ),
          ),
          _heroColumn(context),
        ],
      ),
    );
  }

  Widget _heroColumn(BuildContext context) {
    return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand(context), width: 3),
            ),
            child: GradientAvatar(
                name: user.name, imageUrl: user.avatarUrl, radius: 44),
          ),
          const SizedBox(height: 14),
          Text(user.name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          Text('@${user.username}',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
          if (user.position != null || user.city != null) ...[
            const SizedBox(height: 12),
            GradientPill(
              icon: positionIcon(user.position),
              text: [user.position, user.city]
                  .where((e) => e != null)
                  .join(' · '),
            ),
          ],
          if (user.flagged) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.flag, color: AppColors.danger, size: 16),
                  SizedBox(width: 6),
                  Text('Flagged for repeated score disputes',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.iconAccent(context).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.iconAccent(context)),
            ),
            const SizedBox(height: 10),
            GradientText(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
