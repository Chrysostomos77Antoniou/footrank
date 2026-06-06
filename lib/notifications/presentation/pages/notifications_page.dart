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

  ({String emoji, Color color}) _styleFor(String type) {
    switch (type) {
      case 'match_request':
        return (emoji: '⚽', color: AppColors.lime);
      case 'match_accepted':
        return (emoji: '✅', color: AppColors.success);
      case 'match_reminder':
        return (emoji: '⏰', color: AppColors.gold);
      case 'player_invite':
        return (emoji: '✉️', color: AppColors.lime);
      default:
        return (emoji: '🔔', color: AppColors.lime);
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
                    Center(child: Text('🔔', style: TextStyle(fontSize: 48))),
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
                  final s = _styleFor(n.type);
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
                              child: Text(s.emoji,
                                  style: const TextStyle(fontSize: 22)),
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
                                decoration: const BoxDecoration(
                                  color: AppColors.lime,
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
