import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/services/fcm_token_service.dart';
import 'package:footrank/services/supabase_service.dart';

/// Random string used to bind an Apple sign-in request to the resulting ID
/// token, mitigating replay attacks. Apple receives its SHA-256 hash;
/// Supabase verifies against the raw value.
String _randomNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();

class AuthRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const _redirectUrl = 'io.supabase.footrank://login-callback';

  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _client.auth.signUp(email: email, password: password);

  // supabase_flutter's default launch mode (platformDefault) opens an
  // in-app browser view, which is unreliable at handing the custom
  // io.supabase.footrank:// redirect back to the app on iOS (and Google's
  // own OAuth already refuses to run inside any embedded webview at all).
  // Forcing the real external browser fixes both.
  Future<void> signInWithGoogle() => _client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: _redirectUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
  );

  /// Sign in with Apple. On iOS/macOS this uses Apple's native
  /// AuthenticationServices sheet (Face ID/passcode, no browser at all) --
  /// required by Apple's Sign in with Apple design guidelines, and how every
  /// polished app does it. Other platforms fall back to the web-based OAuth
  /// redirect, since native Sign in with Apple isn't available there.
  Future<void> signInWithApple() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) {
      await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return;
    }

    final rawNonce = _randomNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256Hex(rawNonce),
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple sign-in did not return an ID token.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple only ever sends the user's name on the very first authorization
    // for this app -- capture it into user_metadata now (the profile setup
    // screen's pre-fill reads it from there) since it will never be sent
    // again on subsequent sign-ins.
    final fullName = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().join(' ').trim();
    if (fullName.isNotEmpty) {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': fullName}),
      );
    }
  }

  /// Sign in with Facebook. Functional once the Facebook provider is enabled
  /// in Supabase (needs a Facebook app's ID + secret).
  Future<void> signInWithFacebook() => _client.auth.signInWithOAuth(
    OAuthProvider.facebook,
    redirectTo: _redirectUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
  );

  /// Sends a password reset email to [email] so the user can recover access.
  /// The email link deep-links back into the app (the recovery event then routes
  /// to the "set a new password" screen).
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: _redirectUrl);

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
