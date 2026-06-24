import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/theme_controller.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/notifications/data/notification_repository.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/routing/app_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with ThemeRepaintMixin {
  final _notifRepo = NotificationRepository();
  Future<int> _unread = Future.value(0);
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
  }

  void _refreshUnread() {
    setState(() {
      _unread = _notifRepo.unreadCount();
    });
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    // Drop cached state and tell every tab to re-fetch fresh data.
    ProfileRepository.invalidateCache();
    triggerAppRefresh();
    String message;
    try {
      final count = await _notifRepo
          .unreadCount()
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _unread = Future.value(count);
      });
      message = 'Synced — data refreshed';
    } on TimeoutException {
      message = 'Sync timed out — check your connection';
    } catch (e) {
      message = 'Sync failed: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              FadeSlideIn(
                child: Row(
                  children: [
                    const BrandLogo(size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 13)),
                          const GradientText(
                            'FootRank',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    PressableScale(
                      onTap: _sync,
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        radius: 16,
                        child: _syncing
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: AppColors.iconAccent(context),
                                ),
                              )
                            : Icon(Icons.sync,
                                color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FutureBuilder<int>(
                      future: _unread,
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return PressableScale(
                          onTap: () async {
                            await context.push(AppRoutes.notifications);
                            _refreshUnread();
                          },
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            radius: 16,
                            child: Badge(
                              isLabelVisible: count > 0,
                              label: Text('$count'),
                              child: Icon(Icons.notifications_outlined,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: _HeroBanner(),
              ),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: _ActionCard(
                  emoji: '',
                  iconWidget: Icon(Icons.notifications_active_outlined,
                      color: AppColors.iconAccent(context)),
                  color: AppColors.iconAccent(context),
                  title: 'Notifications',
                  subtitle: 'Match & team updates',
                  onTap: () async {
                    await context.push(AppRoutes.notifications);
                    _refreshUnread();
                  },
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 260),
                child: _ActionCard(
                  emoji: '',
                  iconWidget: Icon(Icons.person_search_outlined,
                      color: AppColors.iconAccent(context)),
                  color: AppColors.iconAccent(context),
                  title: 'Free Agents',
                  subtitle: 'Find players without a team',
                  onTap: () => context.push(AppRoutes.freeAgents),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 340),
                child: _ActionCard(
                  emoji: '',
                  iconWidget: Icon(Icons.mail_outline,
                      color: AppColors.iconAccent(context)),
                  color: AppColors.iconAccent(context),
                  title: 'Team Invitations',
                  subtitle: 'Invitations from team captains',
                  onTap: () => context.push(AppRoutes.invitations),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final onBrand = AppColors.onBrand(context);
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.brandGrad(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand(context).withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Soft sheen circles for a subtle shine.
            Positioned(
              right: -30,
              top: -40,
              child: _circle(110, onBrand.withValues(alpha: 0.12)),
            ),
            Positioned(
              right: 44,
              bottom: -54,
              child: _circle(96, onBrand.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Climb the ranks',
                            style: TextStyle(
                                fontFamily: 'Sora',
                                color: onBrand,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 5),
                        Text(
                          'Win matches to boost your Pitch Power and lead the leaderboard.',
                          style: TextStyle(
                              color: onBrand.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.emoji_events, color: onBrand, size: 42),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _ActionCard extends StatelessWidget {
  final String emoji;
  final Widget? iconWidget;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.emoji,
    this.iconWidget,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: iconWidget ??
                Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios,
              size: 16,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
