import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session (access + refresh token) in the iOS Keychain /
/// Android Keystore instead of plain app preferences, so it can't be copied
/// off a rooted phone or out of an unencrypted backup.
///
/// Existing installs are migrated on first launch: the session saved by the
/// default storage is moved here and deleted from preferences, so nobody is
/// signed out by the update. If the secure store is unavailable on a device,
/// reads fall back to "no session" (the user signs in again) rather than
/// crashing.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      if (await _storage.containsKey(key: persistSessionKey)) return;
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy != null) {
        await _storage.write(key: persistSessionKey, value: legacy);
        await prefs.remove(persistSessionKey);
      }
    } catch (e) {
      debugPrint('Secure session migration failed: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _storage.containsKey(key: persistSessionKey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: persistSessionKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: persistSessionKey);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: persistSessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint('Secure session save failed: $e');
    }
  }
}
