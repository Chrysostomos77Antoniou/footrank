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

  Future<void> signOut() => _client.auth.signOut();

  bool get isNewUser {
    final user = currentUser;
    if (user == null) return false;
    final created = DateTime.tryParse(user.createdAt);
    if (created == null) return false;
    return DateTime.now().difference(created).inSeconds < 30;
  }
}
