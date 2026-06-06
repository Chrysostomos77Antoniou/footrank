import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/services/supabase_service.dart';

class ProfileRepository {
  static const _table = 'users';

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
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Fetches any user's profile by id (for viewing other players).
  Future<UserModel?> fetchUserById(String id) async {
    final data = await SupabaseService.client
        .from(_table)
        .select()
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
        .select()
        .single();

    _cachedHasProfile = true;
    return UserModel.fromJson(inserted);
  }

  /// Updates the current user's editable profile fields.
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
        .select()
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
