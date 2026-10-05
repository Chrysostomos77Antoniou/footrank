import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/payment/data/promo_repository.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/profile/presentation/widgets/profile_avatar.dart';
import 'package:footrank/routing/app_router.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/core/widgets/feedback.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with ThemeRepaintMixin {
  final _profileRepo = ProfileRepository();
  final _authRepo = AuthRepository();
  final _teamRepo = TeamRepository();
  final _matchRepo = MatchRepository();
  late Future<UserModel?> _profileFuture;
  late Future<({String? teamId, List<MatchModel> matches})> _historyFuture;
  late Future<({int rank, int total})?> _rankFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _profileRepo.fetchMyProfile();
    _historyFuture = _loadHistory();
    _rankFuture = _loadRank();
    appRefresh.addListener(_refresh);
  }

  Future<({String? teamId, List<MatchModel> matches})> _loadHistory() async {
    final team = await _teamRepo.fetchMyTeam();
    if (team == null) return (teamId: null, matches: <MatchModel>[]);
    final all = await _matchRepo.fetchTeamMatches(team.id);
    final completed = all
        .where((m) => m.status == 'completed')
        .take(10)
        .toList();
    return (teamId: team.id, matches: completed);
  }

  /// Global Pitch Power rank for the hero card; a failure just hides the number.
  Future<({int rank, int total})?> _loadRank() async {
    try {
      final card = await _profileRepo.fetchMyRankCard();
      if (card == null) return null;
      return (rank: card.rank, total: card.total);
    } catch (_) {
      return null;
    }
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
      _rankFuture = _loadRank();
      _profileFuture = _profileRepo.fetchMyProfile();
    });
  }

  Future<void> _signOut() async {
    try {
      await _authRepo.signOut();
    } catch (e) {
      if (mounted) {
        showError(context, 'Sign out failed: ${friendlyError(e)}');
      }
      return;
    }
    if (mounted) context.go(AppRoutes.login);
  }

  Future<void> _openLegal(String path, String label) async {
    final uri = Uri.parse(
      'https://chrysostomos77antoniou.github.io/footrank/$path',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showError(context, 'Could not open the $label');
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
          'captain. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
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
        showError(context, e);
      }
    }
  }

  Future<void> _openEdit(UserModel user) async {
    final updated = await context.push<bool>(
      AppRoutes.editProfile,
      extra: user,
    );
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
              return const LoadingView();
            }
            if (snapshot.hasError) {
              return ErrorView(
                message: friendlyError(snapshot.error!),
                onRetry: _refresh,
              );
            }
            final user = snapshot.data;
            if (user == null) {
              return const EmptyView(
                icon: Icons.person_off_outlined,
                title: 'No profile found',
              );
            }
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Profile',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: themeController,
                        builder: (context, _) {
                          final mode = themeController.mode;
                          final (icon, label) = switch (mode) {
                            ThemeMode.system => (
                                Icons.brightness_auto,
                                'Theme: Auto'
                              ),
                            ThemeMode.light => (
                                Icons.light_mode,
                                'Theme: Light'
                              ),
                            ThemeMode.dark => (Icons.dark_mode, 'Theme: Dark'),
                          };
                          return _SquareIconButton(
                            icon: icon,
                            tooltip: label,
                            onTap: themeController.toggle,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _SquareIconButton(
                        icon: Icons.logout,
                        tooltip: 'Sign Out',
                        onTap: _signOut,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    child: _ProfileHero(
                      user: user,
                      rankFuture: _rankFuture,
                      onEdit: () => _openEdit(user),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: Row(
                      children: [
                        _StatCard(
                          label: 'Matches',
                          animateTo: user.matchesPlayed,
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          label: 'Reliability',
                          // A player with no matches has no track record yet.
                          value: user.matchesPlayed == 0 ? 'New' : null,
                          animateTo: user.reliability,
                          suffix: '%',
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          label: 'Behavior',
                          value: user.behaviorLabel,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 240),
                    child: _MatchHistory(future: _historyFuture),
                  ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 260),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Column(
                        children: [
                          if (PromoRepository.isOpen)
                            _SettingsRow(
                              icon: Icons.confirmation_number_outlined,
                              label: 'Promo code',
                              trailing: Icons.chevron_right,
                              onTap: () => context.push(AppRoutes.promoCode),
                            ),
                          _SettingsRow(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Privacy Policy',
                            trailing: Icons.open_in_new,
                            onTap: () =>
                                _openLegal('privacy.html', 'privacy policy'),
                          ),
                          _SettingsRow(
                            icon: Icons.description_outlined,
                            label: 'Terms of Service',
                            trailing: Icons.open_in_new,
                            onTap: () =>
                                _openLegal('terms.html', 'terms of service'),
                          ),
                          _SettingsRow(
                            icon: Icons.code,
                            label: 'Open Source Licenses',
                            trailing: Icons.chevron_right,
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'FootRank',
                            ),
                          ),
                          _SettingsRow(
                            icon: Icons.delete_outline,
                            label: 'Delete account',
                            danger: true,
                            isLast: true,
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

/// Fill of a raised control that sits on the screen background (matches the
/// card surface).
Color _controlFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkCard
        : AppColors.lightCard;

/// 11 / 700, letter-spaced, uppercase muted label.
TextStyle _sectionLabelStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.muted(context),
    );

/// 44px rounded-square icon button used in the title row.
class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _controlFill(context),
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
          child: Icon(icon,
              size: 22, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}

/// One 52px row of the settings list.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;
  final bool danger;
  final bool isLast;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.danger = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.dangerText(context)
        : Theme.of(context).colorScheme.onSurface;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(color: AppColors.border(context))),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: danger
                    ? AppColors.dangerText(context)
                    : AppColors.onChip(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, size: 18, color: AppColors.muted(context)),
            ],
          ),
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
          return const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: SkeletonList(count: 2, itemHeight: 48),
          );
        }
        if (data?.teamId == null || matches.isEmpty) {
          return const SizedBox.shrink();
        }
        final myTeamId = data!.teamId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8, top: 6),
                child: Text(
                  'MATCH HISTORY',
                  style: _sectionLabelStyle(context),
                ),
              ),
              GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < matches.length; i++) ...[
                      if (i > 0)
                        Divider(
                            height: 1, color: AppColors.border(context)),
                      _historyRow(context, matches[i], myTeamId),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
    Color color = AppColors.muted(context);
    if (myScore != null && oppScore != null) {
      if (myScore > oppScore) {
        result = 'WON';
        color = AppColors.brand(context);
      } else if (myScore < oppScore) {
        result = 'LOST';
        color = AppColors.dangerText(context);
      }
    }
    final d = m.scheduledAt.toLocal();
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs ${oppName ?? 'Opponent'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSemantic.labelGap),
                  Text(
                    '${m.homeScore ?? '-'} - ${m.awayScore ?? '-'} · $when',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius:
                    BorderRadius.circular(AppSemantic.statusPillRadius),
              ),
              child: Text(
                result,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Midfielder" -> "MID" etc. for the compact position chip.
String _positionAbbr(String position) => switch (position) {
      'Goalkeeper' => 'GK',
      'Defender' => 'DEF',
      'Midfielder' => 'MID',
      'Forward' => 'FWD',
      _ => position,
    };

/// 1500 -> "1,500".
String _thousands(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class _ProfileHero extends StatelessWidget {
  final UserModel user;
  final Future<({int rank, int total})?> rankFuture;
  final VoidCallback onEdit;
  const _ProfileHero({
    required this.user,
    required this.rankFuture,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.muted(context);
    final avatarUrl = user.avatarUrl;
    final chipText = [
      if (user.position != null) _positionAbbr(user.position!),
      if (user.city != null) user.city!,
    ].join(' · ');

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    name: user.name,
                    image: avatarUrl != null && avatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(avatarUrl)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                          if (chipText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.chip(context),
                                borderRadius: BorderRadius.circular(
                                    AppSemantic.statusPillRadius),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 14,
                                    color: isDark
                                        ? const Color(0xFFD5DCE3)
                                        : AppColors.limeDeep,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      chipText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? const Color(0xFFD5DCE3)
                                            : AppColors.limeDeep,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Tooltip(
                  message: 'Edit Profile',
                  child: PressableScale(
                    onTap: onEdit,
                    semanticLabel: 'Edit Profile',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.chip(context),
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: isDark ? scheme.onSurface : AppColors.limeDeep,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (user.flagged) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.14),
                borderRadius:
                    BorderRadius.circular(AppSemantic.statusPillRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag,
                      color: AppColors.dangerText(context), size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Flagged for repeated score disputes',
                      style: TextStyle(
                        color: AppColors.dangerText(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 18),
            color: AppColors.border(context),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PITCH POWER', style: _sectionLabelStyle(context)),
                      const SizedBox(height: 4),
                      _PowerNumber(value: user.elo),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: AppColors.border(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CITY RANK', style: _sectionLabelStyle(context)),
                      const SizedBox(height: 4),
                      _RankValue(future: rankFuture),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _bigNumberStyle(BuildContext context, Color color) => TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 36,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.4,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Pitch Power in 36px accent, rolling up unless reduced motion is on.
class _PowerNumber extends StatelessWidget {
  final int value;
  const _PowerNumber({required this.value});

  @override
  Widget build(BuildContext context) {
    final style = _bigNumberStyle(context, AppColors.brand(context));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: reduceMotion(context) ? Duration.zero : AppMotion.count,
        curve: AppMotion.standard,
        builder: (context, v, _) =>
            Text(_thousands(v.round()), maxLines: 1, style: style),
      ),
    );
  }
}

/// "#72 of 121", or a dash while the rank is loading or unavailable.
class _RankValue extends StatelessWidget {
  final Future<({int rank, int total})?> future;
  const _RankValue({required this.future});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return FutureBuilder<({int rank, int total})?>(
      future: future,
      builder: (context, snap) {
        final data = snap.data;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                data == null ? '–' : '#${_thousands(data.rank)}',
                maxLines: 1,
                style: _bigNumberStyle(context, onSurface),
              ),
              if (data != null) ...[
                const SizedBox(width: 6),
                Text(
                  'of ${_thousands(data.total)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted(context),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String? value;
  final int? animateTo;
  final String suffix;

  const _StatCard({
    required this.label,
    this.value,
    this.animateTo,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final numStyle = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Expanded(
      child: SizedBox(
        height: 84,
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Fixed-height value row so every card's label sits on the
              // same baseline whatever the value's font size.
              SizedBox(
                height: 30,
                child: Center(
                  child: (value == null && animateTo != null)
                      ? AnimatedCount(
                          animateTo!,
                          suffix: suffix,
                          style: numStyle,
                          duration: reduceMotion(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 900),
                        )
                      // A text label (e.g. "Unrated") is wider than a short
                      // number, so it shrinks to fit on one line.
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value ?? '',
                            maxLines: 1,
                            softWrap: false,
                            style: numStyle.copyWith(
                              fontSize: animateTo == null && value!.length > 4
                                  ? 19
                                  : 22,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
