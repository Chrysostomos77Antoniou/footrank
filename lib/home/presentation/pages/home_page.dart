import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/notifications/data/notification_repository.dart';
import 'package:footrank/payment/presentation/widgets/pending_fee_banner.dart';
import 'package:footrank/payment/presentation/widgets/promo_code_field.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/team/presentation/widgets/team_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/core/widgets/feedback.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with ThemeRepaintMixin {
  final _notifRepo = NotificationRepository();
  final _teamRepo = TeamRepository();
  final _profileRepo = ProfileRepository();
  late Future<({UserModel profile, int rank, int total})?> _rankFuture;
  Future<int> _unread = Future.value(0);
  bool _syncing = false;
  List<TeamModel> _teams = [];
  bool _teamLoaded = false;
  int _inviteCount = 0;
  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    _rankFuture = _profileRepo.fetchMyRankCard();
    appRefresh.addListener(_reloadRank);
    _refreshUnread();
    _loadTeam();
    _loadInvites();
    appRefresh.addListener(_loadTeam);
    appRefresh.addListener(_loadInvites);
    // Live badge updates -- the moment a new notification lands server-side
    // (a proposal, a confirm, etc.), the bell count refreshes on its own
    // instead of only updating after a manual sync or a trip to the page.
    _notifChannel = _notifRepo.subscribeToNew(_refreshUnread);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_reloadRank);
    appRefresh.removeListener(_loadTeam);
    appRefresh.removeListener(_loadInvites);
    _notifRepo.unsubscribe(_notifChannel);
    super.dispose();
  }

  /// Re-fetch the rank card when the user pulls "Sync" so the rank stays
  /// current.
  void _reloadRank() {
    if (!mounted) return;
    setState(() => _rankFuture = _profileRepo.fetchMyRankCard());
  }

  Future<void> _loadInvites() async {
    try {
      final invites = await _teamRepo.fetchMyInvitations();
      if (!mounted) return;
      setState(() => _inviteCount = invites.length);
    } catch (_) {
      // Non-fatal — just don't show a badge.
    }
  }

  void _refreshUnread() {
    setState(() {
      _unread = _notifRepo.unreadCount();
    });
  }

  Future<void> _loadTeam() async {
    try {
      final teams = await _teamRepo.fetchMyTeams();
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _teamLoaded = true;
      });
    } catch (_) {
      // Non-fatal: just hide the team-dependent cards if we can't resolve teams.
      if (!mounted) return;
      setState(() {
        _teams = [];
        _teamLoaded = true;
      });
    }
  }

  Future<void> _createMatch() async {
    // Only a team's captain can open a match request (enforced server-side).
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final captained = _teams.where((t) => t.captainId == uid).toList();
    if (captained.isEmpty) {
      showError(context, 'Only a team captain can create a match request.');
      return;
    }
    final team = await chooseTeam(
      context,
      captained,
      title: 'Create a match for…',
    );
    if (!mounted || team == null) return;

    // Matches are 5-a-side -- fail fast with a clear message instead of
    // letting the request hit the server's "at least 5 players" check.
    final members = await _teamRepo.fetchMembers(team.id);
    if (!mounted) return;
    if (members.length < 5) {
      showError(
        context,
        '${team.name} needs at least 5 players before you can create a '
        'match (currently ${members.length}).',
      );
      return;
    }

    context.push(AppRoutes.createMatch, extra: team.id);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    // Drop cached state and tell every tab to re-fetch fresh data.
    ProfileRepository.invalidateCache();
    triggerAppRefresh();
    // Sync reports three genuinely different outcomes, so it picks the helper
    // per branch rather than funnelling them all through one grey pill —
    // "refreshed" and "failed" should never look the same.
    void Function() report;
    try {
      final count = await _notifRepo.unreadCount().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _unread = Future.value(count);
      });
      report = () => showSuccess(context, 'Synced — data refreshed');
    } on TimeoutException {
      report =
          () => showError(context, 'Sync timed out — check your connection');
    } catch (e) {
      report = () => showError(context, 'Sync failed: ${friendlyError(e)}');
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    report();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 108),
            children: [
              FadeSlideIn(child: _buildHeader(context)),
              const SizedBox(height: AppSpacing.sm),
              // Outstanding match fee, if any -- placed above the hero so it is
              // the first thing under the header. The fee card inside match
              // detail was not discoverable: a captain had to already know a
              // fee existed and go looking. Renders nothing when none is owed.
              const PendingFeeBanner(),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: _HeroBanner(future: _rankFuture),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Nudge players who aren't on a team yet into the core loop.
              if (_teamLoaded && _teams.isEmpty) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: _NoTeamCard(onChanged: _loadTeam),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // ---- Primary action: the single most important thing to do ----
              if (_teams.isNotEmpty) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: _PrimaryCta(
                    title: 'Create Match',
                    subtitle: _teams.length > 1
                        ? 'Set up a match — pick which team'
                        : 'Set up a match for your team',
                    onTap: _createMatch,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // "Add your promo code" -- only while the promo is open; collapses
              // to a one-line note once a code is active.
              const PromoCodeField(),
              const SizedBox(height: AppSpacing.xxs),
              // ---- Secondary actions ----
              const FadeSlideIn(
                delay: Duration(milliseconds: 240),
                child: _SectionLabel('MANAGE'),
              ),
              FadeSlideIn(
                delay: const Duration(milliseconds: 280),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisExtent: 104,
                  ),
                  children: [
                    _ManageTile(
                      icon: Icons.local_offer_outlined,
                      title: 'Offers',
                      subtitle: 'Partner deals',
                      onTap: () => context.push(AppRoutes.offers),
                    ),
                    _ManageTile(
                      icon: Icons.location_on_outlined,
                      title: 'Courts',
                      subtitle: 'Places to play',
                      onTap: () => context.push(AppRoutes.courts),
                    ),
                    _ManageTile(
                      icon: Icons.search_rounded,
                      title: 'Players',
                      subtitle: 'Find people',
                      onTap: () => context.push(AppRoutes.freeAgents),
                    ),
                    _ManageTile(
                      icon: Icons.mail_outline_rounded,
                      title: 'Invites',
                      subtitle: 'Match requests',
                      badgeCount: _inviteCount,
                      onTap: () async {
                        await context.push(AppRoutes.invitations);
                        _loadInvites();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardFill = isDark ? AppColors.darkCard : AppColors.lightCard;
    return Row(
      children: [
        FutureBuilder<({UserModel profile, int rank, int total})?>(
          future: _rankFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data?.profile;
            final name = (profile?.name ?? '').trim();
            final firstName = name.isEmpty ? 'FootRank' : name.split(RegExp(r'\s+')).first;
            return Row(
              children: [
                _HomeAvatar(name: name, imageUrl: profile?.avatarUrl),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const Spacer(),
        _HeaderButton(
          label: 'Sync',
          onTap: _sync,
          child: AnimatedSwitcher(
            duration: AppMotion.quick,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _syncing
                ? SizedBox(
                    key: const ValueKey('spinner'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.brand(context),
                    ),
                  )
                : Icon(
                    Icons.sync,
                    key: const ValueKey('icon'),
                    size: 22,
                    color: onSurface,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Header bell opens Notifications and carries the unread dot; Offers
        // lives in the MANAGE grid below.
        FutureBuilder<int>(
          future: _unread,
          builder: (context, snapshot) {
            final unread = snapshot.data ?? 0;
            return _HeaderButton(
              label: 'Notifications',
              onTap: () async {
                await context.push(AppRoutes.notifications);
                _refreshUnread();
              },
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 22, color: onSurface),
                  if (unread > 0)
                    Positioned(
                      top: -3,
                      right: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // Light mode: a deep-green ring keeps the lime dot
                          // visible against the white button.
                          border: isDark
                              ? null
                              : Border.all(color: AppColors.limeDeep),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.lime,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardFill, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 44px circular avatar: the player's photo, or their initial on green.
class _HomeAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  const _HomeAvatar({required this.name, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return GradientAvatar(name: name, imageUrl: imageUrl, radius: 22);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'F';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.heroDarkA : AppColors.limeDeep,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// 44x44 rounded-square icon button used in the Home header (sync, bell).
class _HeaderButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget child;
  const _HeaderButton({
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// The rank hero card: the one green surface, with lime numbers in both themes.
class _HeroBanner extends StatelessWidget {
  final Future<({UserModel profile, int rank, int total})?> future;
  const _HeroBanner({required this.future});

  /// 1623 -> "1,623"
  static String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const radius = 24.0;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGrad(context),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : AppColors.limeDeeper.withValues(alpha: 0.28),
            blurRadius: isDark ? 32 : 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Faint centre-circle pitch markings.
            const Positioned(
              right: -70,
              top: -50,
              child: CustomPaint(
                size: Size(220, 220),
                painter: _PitchMarkingsPainter(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: FutureBuilder<({UserModel profile, int rank, int total})?>(
                future: future,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR RANK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.54,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (data != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '#${data.rank}',
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 68,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -1.36,
                                color: AppColors.lime,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'of ${data.total} players',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Text(
                          'Climb the ranks',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.5,
                            color: AppColors.lime,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Win matches to boost your Pitch Power and lead the leaderboard.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                      Container(
                        height: 1,
                        margin: const EdgeInsets.only(top: 16, bottom: 14),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      Row(
                        children: [
                          if (data != null) ...[
                            Text(
                              _fmt(data.profile.elo),
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pitch Power',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.emoji_events_outlined,
                                      size: 16,
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Win matches to climb',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white
                                            .withValues(alpha: 0.92),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two concentric circles and a halfway line, drawn faintly behind the rank.
class _PitchMarkingsPainter extends CustomPainter {
  const _PitchMarkingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.10);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, size.width * 100 / 220, paint);
    canvas.drawCircle(c, size.width * 62 / 220, paint);
    canvas.drawLine(
      Offset(size.width * 10 / 220, c.dy),
      Offset(size.width * 210 / 220, c.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchMarkingsPainter oldDelegate) => false;
}

/// Shown on Home when the signed-in user isn't on a team yet — the single
/// biggest blocker to playing matches. Gives a direct path to create or join.
class _NoTeamCard extends StatelessWidget {
  final VoidCallback onChanged;
  const _NoTeamCard({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final iconColor = isDark ? AppColors.muted(context) : AppColors.brand(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
    );
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're not on a team yet",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Create your own squad or join one with an invite code to start '
            'playing ranked matches and climbing the leaderboard.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.muted(context),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.action,
                    foregroundColor: AppColors.onAction(context),
                    shape: shape,
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    await context.push(AppRoutes.createTeam);
                    onChanged();
                  },
                  child: const Text('Create Team'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: isDark ? onSurface : AppColors.limeDeep,
                    side: isDark
                        ? BorderSide(
                            color: Colors.white.withValues(alpha: 0.24))
                        : const BorderSide(
                            color: AppColors.limeDeep, width: 1.5),
                    shape: shape,
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    await context.push(AppRoutes.joinTeam);
                    onChanged();
                  },
                  child: const Text('Join Team'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small uppercase eyebrow label that separates sections — hierarchy through
/// typography (size + tracking + weight) rather than another heavy heading.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.xxs, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppColors.muted(context),
        ),
      ),
    );
  }
}

/// The one visually-dominant action on Home: a solid lime card (the primary
/// action colour in both themes) so it outranks every card below it.
class _PrimaryCta extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PrimaryCta({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onAction = AppColors.onAction(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.action,
          borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: onAction.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSemantic.buttonRadius),
              ),
              child: Icon(Icons.add_circle_outline, color: onAction, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: onAction,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onAction.withValues(alpha: 0.75),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: onAction, size: 22),
          ],
        ),
      ),
    );
  }
}

/// A tile for the 2x2 "MANAGE" grid on Home.
///
/// Press feel follows the mockup: scale to 0.97 over 160ms on an ease-out
/// curve, and on tap the icon well fills with lime while an accent border
/// sweeps once around the tile. Under reduced motion the scale and the sweep
/// are skipped; the border/well highlight still flashes (a state change, not
/// movement).
class _ManageTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badgeCount;

  const _ManageTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_ManageTile> createState() => _ManageTileState();
}

class _ManageTileState extends State<_ManageTile>
    with SingleTickerProviderStateMixin {
  /// cubic-bezier(0.23, 1, 0.32, 1), the mockup's --ease-out.
  static const _ease = Cubic(0.23, 1, 0.32, 1);
  static const _radius = 22.0;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Timer? _hold;
  bool _down = false;
  bool _active = false;

  @override
  void dispose() {
    _hold?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    if (!reduceMotion(context)) _sweep.forward(from: 0);
    setState(() => _active = true);
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _active = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.brand(context);
    final reduce = reduceMotion(context);
    final fade = reduce ? Duration.zero : const Duration(milliseconds: 200);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final borderColor = _active
        ? accent.withValues(alpha: isDark ? 0.55 : 0.6)
        : AppColors.border(context);

    Widget well = AnimatedContainer(
      duration: fade,
      curve: _ease,
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _active ? AppColors.action : AppColors.chip(context),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(
        widget.icon,
        size: 18,
        color: _active ? AppColors.onAction(context) : AppColors.onChip(context),
      ),
    );
    if (widget.badgeCount > 0) {
      well = Badge(
        label: Text('${widget.badgeCount}'),
        backgroundColor: AppColors.danger,
        child: well,
      );
    }

    return Semantics(
      button: true,
      onTap: _handleTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: reduce ? null : (_) => setState(() => _down = true),
        onTapUp: reduce ? null : (_) => setState(() => _down = false),
        onTapCancel: reduce ? null : () => setState(() => _down = false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 160),
          curve: _ease,
          child: CustomPaint(
            foregroundPainter: _SweepBorderPainter(
              animation: _sweep,
              color: accent,
              radius: _radius,
              ease: _ease,
            ),
            child: AnimatedContainer(
              duration: fade,
              curve: _ease,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.06),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  well,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                          height: 1.2,
                          color: onSurface,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: AppColors.muted(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a 1.5px accent arc that sweeps once around the tile's border, like
/// the mockup's `conic-gradient(from var(--ang), transparent 0 55%, accent 88%,
/// transparent 100%)` ring. The angle runs 0 -> 360deg on an ease-out curve and
/// the ring fades out over the last 30% of the animation.
class _SweepBorderPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  final double radius;
  final Curve ease;

  _SweepBorderPainter({
    required this.animation,
    required this.color,
    required this.radius,
    required this.ease,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || t >= 1) return;
    final angle = ease.transform(t) * 2 * math.pi;
    final opacity = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
    final clear = color.withValues(alpha: 0);
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = SweepGradient(
        colors: [
          clear,
          clear,
          color.withValues(alpha: opacity),
          clear,
        ],
        stops: const [0, 0.55, 0.88, 1],
        // CSS conic angles start at 12 o'clock; Flutter's start at 3 o'clock.
        transform: GradientRotation(angle - math.pi / 2),
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.75), Radius.circular(radius - 0.75)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SweepBorderPainter old) =>
      old.color != color || old.radius != radius;
}
