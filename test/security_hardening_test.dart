import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/auth/data/legal_versions.dart';
import 'package:footrank/services/analytics_consent.dart';
import 'package:footrank/services/secure_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'sb-test-auth-token';

  group('secure session storage', () {
    test('moves an existing session out of plain preferences', () async {
      SharedPreferences.setMockInitialValues({key: '{"access_token":"a"}'});
      FlutterSecureStorage.setMockInitialValues({});
      final s = SecureSessionStorage(persistSessionKey: key);
      await s.initialize();

      expect(await s.hasAccessToken(), isTrue);
      expect(await s.accessToken(), '{"access_token":"a"}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNull, reason: 'plain copy must be gone');
    });

    test('saves, reads and removes the session', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = SecureSessionStorage(persistSessionKey: key);
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);

      await s.persistSession('session');
      expect(await s.accessToken(), 'session');
      await s.removePersistedSession();
      expect(await s.hasAccessToken(), isFalse);
    });

    test('an already-secure session is not overwritten', () async {
      SharedPreferences.setMockInitialValues({key: 'old'});
      FlutterSecureStorage.setMockInitialValues({key: 'new'});
      final s = SecureSessionStorage(persistSessionKey: key);
      await s.initialize();
      expect(await s.accessToken(), 'new');
    });
  });

  group('usage statistics consent', () {
    test('off until the user opts in', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AnalyticsConsent.isOptedIn(), isFalse);
      await AnalyticsConsent.set(true);
      expect(await AnalyticsConsent.isOptedIn(), isTrue);
      await AnalyticsConsent.set(false);
      expect(await AnalyticsConsent.isOptedIn(), isFalse);
    });
  });

  test('privacy policy version was bumped so everyone re-consents', () {
    expect(LegalVersions.privacy.compareTo('2026-10-10'), greaterThan(0));
  });
}
