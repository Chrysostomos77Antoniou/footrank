import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('offline auth failure becomes a friendly network message', () {
    final err = AuthRetryableFetchException(
      message: 'ClientException with SocketException: Failed host lookup',
    );
    expect(friendlyError(err), contains('Network error'));
    expect(friendlyError(const SocketException('x')), contains('Network error'));
  });

  test('timeouts get a clear message', () {
    expect(friendlyError(TimeoutException('t')), contains('timed out'));
  });

  test('regular auth errors keep their own message', () {
    expect(friendlyError(const AuthException('Invalid login credentials')),
        'Invalid login credentials');
  });
}
