import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// Permanently deletes the current user's account and all their data.
  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    await _client.auth.signOut();
  }

  Future<void> signOut() => _client.auth.signOut();

  bool get isNewUser {
    final user = currentUser;
    if (user == null) return false;
    final created = DateTime.tryParse(user.createdAt);
    if (created == null) return false;
    return DateTime.now().difference(created).inSeconds < 30;
  }
}
