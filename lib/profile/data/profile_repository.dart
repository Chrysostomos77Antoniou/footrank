import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/services/supabase_service.dart';

class ProfileRepository {
  static const _table = 'users';

  /// Explicit allow-list of public-safe profile columns.
  ///
  /// We never use a bare `.select()` (SELECT *) on the `users` table: that would
  /// return every column the RLS policy allows for the row, so any future column
  /// added to `users` (email, auth metadata, internal flags, etc.) would be
  /// silently exposed to every viewer. Keep this list to exactly the fields
  /// `UserModel.fromJson` consumes.
  static const _publicColumns =
      'id,name,username,city,position,elo,reliability,'
      'behavior_positive,behavior_negative,matches_played,avatar_url,'
      'dispute_count,flagged,created_at';

  /// Cached "does the current user have a profile" flag, to avoid hitting the
  /// database on every navigation. Reset on sign-out / sign-in.
  static bool? _cachedHasProfile;

  static void invalidateCache() => _cachedHasProfile = null;

  /// Returns the current user's profile, or null if it hasn't been created yet.
  Future<UserModel?> fetchMyProfile() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await SupabaseService.client
        .from(_table)
        .select(_publicColumns)
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// The signed-in user's profile plus their global Pitch Power (elo) rank and
  /// the total number of ranked players. Returns null if there's no profile yet.
  Future<({UserModel profile, int rank, int total})?> fetchMyRankCard() async {
    final profile = await fetchMyProfile();
    if (profile == null) return null;

    // One light query of every player's elo, to compute rank + total locally.
    // Rank = how many players sit strictly above this elo, +1.
    final rows =
        await SupabaseService.client.from(_table).select('id, elo') as List;
    final higher = rows
        .where((r) => ((r as Map)['elo'] as int? ?? 1500) > profile.elo)
        .length;

    return (profile: profile, rank: higher + 1, total: rows.length);
  }

  /// Fetches any user's profile by id (for viewing other players).
  Future<UserModel?> fetchUserById(String id) async {
    final data = await SupabaseService.client
        .from(_table)
        .select(_publicColumns)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  Future<bool> hasProfile() async {
    if (_cachedHasProfile == true) return true;
    final exists = (await fetchMyProfile()) != null;
    _cachedHasProfile = exists;
    return exists;
  }

  /// Creates the user record after signup.
  Future<UserModel> createProfile({
    required String name,
    required String username,
    String? city,
    String? position,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user');
    }

    final inserted = await SupabaseService.client
        .from(_table)
        .insert({
          'id': userId,
          'name': name,
          'username': username,
          'city': city,
          'position': position,
        })
        .select(_publicColumns)
        .single();

    _cachedHasProfile = true;
    return UserModel.fromJson(inserted);
  }

  /// Updates the current user's editable profile fields.
  /// Returns the current user's saved contact phone (owner-only table), or null.
  Future<String?> fetchMyPhone() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await SupabaseService.client
        .from('user_contacts')
        .select('phone')
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['phone'] as String?;
  }

  /// Upserts the current user's contact phone into the locked contacts table.
  Future<void> saveMyPhone(String? phone) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) throw StateError('No authenticated user');
    await SupabaseService.client.from('user_contacts').upsert({
      'user_id': userId,
      'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<UserModel> updateProfile({
    required String name,
    required String username,
    String? city,
    String? position,
    String? avatarUrl,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) throw StateError('No authenticated user');

    final updated = await SupabaseService.client
        .from(_table)
        .update({
          'name': name,
          'username': username,
          'city': city,
          'position': position,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        })
        .eq('id', userId)
        .select(_publicColumns)
        .single();

    return UserModel.fromJson(updated);
  }

  /// Uploads avatar bytes to storage and returns the public URL.
  Future<String> uploadAvatar(List<int> bytes, String fileExt) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) throw StateError('No authenticated user');

    final ext = normalizeImageExt(fileExt);
    final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await SupabaseService.client.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: imageContentType(ext), upsert: false),
        );
    return SupabaseService.client.storage.from('avatars').getPublicUrl(path);
  }
}

/// Normalizes an image extension to one of the allowed types.
String normalizeImageExt(String ext) {
  final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
  return (e == 'jpg' || e == 'png' || e == 'webp') ? e : 'jpg';
}

/// Content-type for an allowed image extension.
String imageContentType(String ext) {
  switch (ext.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}
