import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/notification_model.dart';
import 'package:footrank/notifications/data/notification_repository.dart';
import 'package:footrank/services/notification_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/theme_controller.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with ThemeRepaintMixin {
  final _repo = NotificationRepository();
  late Future<List<NotificationModel>> _future;
  RealtimeChannel? _notifChannel;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
    _repo.markAllRead();
    // Live-append anything that arrives while this page is open.
    _notifChannel = _repo.subscribeToNew(_reload);
  }

  @override
  void dispose() {
    _repo.unsubscribe(_notifChannel);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _repo.fetchAll();
    });
  }

  /// Icon, icon colour and icon-well fill for a notification type. Semantic
  /// colours (confirmed / cancelled / reminder) stay recognisable in both
  /// themes; everything else uses the accent.
  ({IconData icon, Color fg, Color bg}) _styleFor(
      BuildContext context, String type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = (
      fg: AppColors.brand(context),
      bg: isDark
          ? AppColors.lime.withValues(alpha: 0.16)
          : AppColors.lightChip,
    );
    switch (type) {
      case 'match_accepted':
        const green = Color(0xFF4ADE80);
        return (
          icon: Icons.check_circle_outline,
          fg: isDark ? green : AppColors.limeDeep,
          bg: isDark
              ? green.withValues(alpha: 0.16)
              : const Color(0xFFDDF3E5),
        );
      case 'match_cancelled':
        return (
          icon: Icons.event_busy,
          fg: AppColors.dangerText(context),
          bg: isDark
              ? AppColors.dangerText(context).withValues(alpha: 0.16)
              : const Color(0xFFFCE4E2),
        );
      case 'match_reminder':
        const amber = Color(0xFFF5C451);
        return (
          icon: Icons.alarm,
          fg: isDark ? amber : const Color(0xFF8A5A00),
          bg: isDark
              ? amber.withValues(alpha: 0.16)
              : const Color(0xFFFFF1CC),
        );
      case 'match_request':
        return (icon: Icons.sports_soccer, fg: accent.fg, bg: accent.bg);
      case 'player_invite':
        return (icon: Icons.mail_outline, fg: accent.fg, bg: accent.bg);
      default:
        return (
          icon: Icons.notifications_outlined,
          fg: accent.fg,
          bg: accent.bg
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const _PageHeader(title: 'Notifications'),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: FutureBuilder<List<NotificationModel>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LoadingView();
                      }
                      if (snapshot.hasError) {
                        return ErrorView(onRetry: _reload);
                      }
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) {
                        return ListView(
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(
                              icon: Icons.notifications_off_outlined,
                              title: 'No notifications yet',
                              hint:
                                  'Match requests, confirmations and reminders '
                                  'will show up here.',
                            ),
                          ],
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            AppSemantic.screenPadding, AppSpacing.xxs,
                            AppSemantic.screenPadding, 100),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final n = items[i];
                          final s = _styleFor(context, n.type);
                          return FadeSlideIn(
                            delay: AppMotion.staggerFor(i),
                            animateOnceId: n.id,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _NotificationCard(
                                notification: n,
                                icon: s.icon,
                                iconColor: s.fg,
                                iconBg: s.bg,
                                onTap: () => handleNotificationTap(
                                  type: n.type,
                                  referenceId: n.referenceId,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Back button + 26/800 screen title.
class _PageHeader extends StatelessWidget {
  final String title;
  const _PageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSemantic.screenPadding, AppSpacing.md, AppSemantic.screenPadding,
          AppSpacing.sm),
      child: Row(
        children: [
          PressableScale(
            onTap: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Back',
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
              child: Icon(Icons.arrow_back_rounded, size: 22, color: onSurface),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.26,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One notification row. Unread rows get an accent-tinted border, bolder title
/// and a dot; read rows recede.
class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final n = notification;
    final unread = !n.read;
    final borderColor = unread
        ? (isDark
            ? AppColors.lime.withValues(alpha: 0.28)
            : AppColors.limeDeep.withValues(alpha: 0.35))
        : AppColors.border(context);
    final readTitle = isDark ? const Color(0xFFDDE3E9) : const Color(0xFF2B3A31);

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
          border: Border.all(color: borderColor),
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
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: -0.15,
                      color: unread ? onSurface : readTitle,
                    ),
                  ),
                  if (n.body != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.body!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.muted(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 14),
              Semantics(
                label: 'Unread',
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.lime,
                    shape: BoxShape.circle,
                    border: isDark
                        ? null
                        : Border.all(color: AppColors.limeDeep, width: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
