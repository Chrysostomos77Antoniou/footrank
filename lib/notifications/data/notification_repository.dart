import 'package:footrank/models/notification_model.dart';
import 'package:footrank/services/supabase_service.dart';

class NotificationRepository {
  static const _table = 'notifications';

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

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
