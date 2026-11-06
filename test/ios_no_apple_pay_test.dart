import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App Review rejected 1.1.5 (245) under Guideline 2.1 because the binary
/// linked PassKit (via flutter_stripe / StripeApplePay) and declared Apple Pay,
/// while the payment sheet never showed it. These strings must stay out of the
/// iOS build path.
const _forbidden = <String>[
  'com.apple.developer.in-app-payments',
  'merchant.com.footballcy.footrank',
  'PassKit',
  'StripeApplePay',
  'flutter_stripe',
  'stripe_ios',
];

void main() {
  test('iOS build path does not declare Apple Pay or link PassKit', () {
    final files = <File>[
      File('ios/Runner/Runner.entitlements'),
      File('ios/Runner/Info.plist'),
      File('ios/Podfile'),
      File('ios/Runner.xcodeproj/project.pbxproj'),
      File('pubspec.yaml'),
      File('pubspec.lock'),
    ];

    for (final file in files) {
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final text = file.readAsStringSync();
      for (final needle in _forbidden) {
        expect(
          text.contains(needle),
          isFalse,
          reason: '${file.path} still contains "$needle"',
        );
      }
    }
  });
}
