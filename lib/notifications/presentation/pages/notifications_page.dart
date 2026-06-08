import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/notification_model.dart';
import 'package:footrank/notifications/data/notification_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repo = NotificationRepository();
  late Future<List<NotificationModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchAll();
    _repo.markAllRead();
  }

  void _reload() {
    setState(() {
      _future = _repo.fetchAll();
    });
  }

  ({IconData icon, Color color}) _styleFor(BuildContext context, String type) {
    final accent = AppColors.iconAccent(context);
    switch (type) {
      case 'match_request':
        return (icon: Icons.sports_soccer, color: accent);
      case 'match_accepted':
        return (icon: Icons.check_circle_outline, color: AppColors.success);
      case 'match_reminder':
        return (icon: Icons.alarm, color: AppColors.gold);
      case 'player_invite':
        return (icon: Icons.mail_outline, color: accent);
      default:
        return (icon: Icons.notifications_outlined, color: accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AmbientBackground(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<NotificationModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                    child: Text('Something went wrong. Pull to retry.'));
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                        child: Icon(Icons.notifications_off_outlined,
                            size: 48, color: Colors.grey)),
                    SizedBox(height: 12),
                    Center(child: Text('No notifications yet')),
                  ],
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i];
                  final s = _styleFor(context, n.type);
                  return FadeSlideIn(
                    delay: Duration(milliseconds: 30 * i),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: s.color.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Icon(s.icon, color: s.color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  if (n.body != null) ...[
                                    const SizedBox(height: 2),
                                    Text(n.body!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ],
                                ],
                              ),
                            ),
                            if (!n.read)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.brand(context),
                                  shape: BoxShape.circle,
                                ),
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
    );
  }
}
