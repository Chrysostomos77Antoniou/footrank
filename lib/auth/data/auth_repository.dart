import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/services/fcm_token_service.dart';
import 'package:footrank/services/supabase_service.dart';

class AuthRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _redirectUrl = 'io.supabase.footrank://login-callback';

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) =>
      _client.auth.signUp(email: email, password: password);

  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
      );

  /// Sign in with Apple. Functional once the Apple provider is configured in
  /// Supabase (requires a paid Apple Developer account); works on iOS/macOS.
  Future<void> signInWithApple() => _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _redirectUrl,
      );

  /// Sign in with Facebook. Functional once the Facebook provider is enabled
  /// in Supabase (needs a Facebook app's ID + secret).
  Future<void> signInWithFacebook() => _client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: _redirectUrl,
      );

  /// Sends a password reset email to [email] so the user can recover access.
  /// The email link deep-links back into the app (the recovery event then routes
  /// to the "set a new password" screen).
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(
        email,
        redirectTo: _redirectUrl,
      );

  /// Sets a new password for the user during an active recovery session
  /// (after they followed the reset link from their email).
  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  /// Permanently deletes the current user's account and all their data.
  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    await _client.auth.signOut();
  }

  Future<void> signOut() async {
    // Drop this device's push token first (while still authenticated) so a
    // shared device never delivers the next user's alerts to the previous one.
    await FcmTokenService.remove();
    await _client.auth.signOut();
  }

  bool get isNewUser {
    final user = currentUser;
    if (user == null) return false;
    final created = DateTime.tryParse(user.createdAt);
    if (created == null) return false;
    return DateTime.now().difference(created).inSeconds < 30;
  }
}
