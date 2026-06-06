import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/notifications/data/notification_repository.dart';
import 'package:footrank/routing/app_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _notifRepo = NotificationRepository();
  Future<int> _unread = Future.value(0);

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
                  emoji: '🔔',
                  color: AppColors.brand(context),
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
                  emoji: '📄',
                  iconWidget: const _NoContractIcon(),
                  color: AppColors.brand(context),
                  title: 'Free Agents',
                  subtitle: 'Find players without a team',
                  onTap: () => context.push(AppRoutes.freeAgents),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 340),
                child: _ActionCard(
                  emoji: '✉️',
                  color: AppColors.brand(context),
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brandGrad(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Climb the ranks 🏆',
                    style: TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Win matches to boost your ELO and lead the leaderboard.',
                  style: TextStyle(
                      color: AppColors.onBrand.withValues(alpha: 0.8),
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text('⚽', style: TextStyle(fontSize: 46)),
        ],
      ),
    );
  }
}

/// A contract page with a red ✗ overlaid — "no contract / free agent".
class _NoContractIcon extends StatelessWidget {
  const _NoContractIcon();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      alignment: Alignment.center,
      children: [
        Text('📄', style: TextStyle(fontSize: 24)),
        Icon(Icons.close, color: AppColors.danger, size: 26),
      ],
    );
  }
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
