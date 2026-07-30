import 'package:footrank/models/notification_model.dart';
import 'package:footrank/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  static const _table = 'notifications';

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// Live-subscribes to new notifications for the signed-in user, calling
  /// [onInsert] the instant one lands -- so a badge/list can update the
  /// moment it happens instead of only on the next manual fetch. Returns the
  /// channel so the caller can unsubscribe (via [unsubscribe]) when done.
  RealtimeChannel? subscribeToNew(void Function() onInsert) {
    final uid = _uid;
    if (uid == null) return null;
    final channel = SupabaseService.client.channel('notifications:$uid');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => onInsert(),
        )
        .subscribe();
    return channel;
  }

  void unsubscribe(RealtimeChannel? channel) {
    if (channel != null) SupabaseService.client.removeChannel(channel);
  }

  Future<List<NotificationModel>> fetchAll() async {
    final uid = _uid;
    if (uid == null) return [];
    final data = await SupabaseService.client
        .from(_table)
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final data = await SupabaseService.client
        .from(_table)
        .select('id')
        .eq('user_id', uid)
        .eq('read', false);
    return (data as List).length;
  }

  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    await SupabaseService.client
        .from(_table)
        .update({'read': true})
        .eq('user_id', uid)
        .eq('read', false);
  }
}
