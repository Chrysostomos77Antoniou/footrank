import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  // iOS-registered OAuth client, required for the native picker to launch
  // on iOS at all.
  static const _googleIosClientId =
      '159555623346-s3r9fdk2g0ab2l5sp6kc7ft64eobpfh3.apps.googleusercontent.com';

  // The Web OAuth client already registered with Supabase's Google provider.
  // Passing it as serverClientId makes native Google Sign-In return an
  // idToken whose audience Supabase already trusts, and is required on
  // Android to receive an idToken at all.
  static const _googleServerClientId =
      '159555623346-u1uuaqnl9rc7rtg7af3sc62o8tnj6j70.apps.googleusercontent.com';

  // GoogleSignIn.instance.initialize() must run exactly once (per the
  // package's own contract) before any other call -- cached across every
  // AuthRepository() instance rather than re-run per instance.
  static Future<void>? _googleInit;
  Future<void> _ensureGoogleInitialized() => _googleInit ??= GoogleSignIn
      .instance
      .initialize(
        clientId: _googleIosClientId,
        serverClientId: _googleServerClientId,
      );

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

  /// Sign in with Google. On iOS/Android this uses Google's native account
  /// picker (no browser, no OS "open this app?" prompt) -- how every
  /// polished app does it. Other platforms fall back to the web-based OAuth
  /// redirect, since the native SDK isn't available there.
  ///
  /// Uses google_sign_in v7's `authenticate()`/`GoogleSignIn.instance` API
  /// rather than v6's `GoogleSignIn().signIn()`: v6's iOS implementation
  /// silently embeds its own nonce in the returned ID token (a deprecated-API
  /// quirk) with no way for callers to read or match it, which Supabase
  /// rejects with "Passed nonce and nonce in id_token should either both
  /// exist or not." v7 doesn't have this problem, so no nonce handling is
  /// needed here at all.
  Future<void> signInWithGoogle() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return;
    }

    await _ensureGoogleInitialized();

    const scopes = ['email'];
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return; // user cancelled the picker
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in did not return an ID token.');
    }

    final authorization =
        await account.authorizationClient.authorizationForScopes(scopes) ??
        await account.authorizationClient.authorizeScopes(scopes);

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }

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

  /// Sign in with Facebook. Still using the web-based OAuth redirect for
  /// now -- native login is pending a real Meta Client Token and, on
  /// Android, a public Play Store listing.
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
    // Otherwise the native Google/Facebook pickers silently re-sign the
    // same account back in next time instead of letting the user
    // choose/switch.
    if (_googleInit != null) {
      await GoogleSignIn.instance.signOut();
    }
    await FacebookAuth.instance.logOut();
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
