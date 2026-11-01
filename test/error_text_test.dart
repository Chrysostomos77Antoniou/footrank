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

  group('venue rejections from the server', () {
    String msg(String code) =>
        friendlyError(PostgrestException(message: code, code: 'P0001'));

    test('each bad_venue reason has its own plain-English message', () {
      expect(msg('bad_venue:length'), contains('2 and 60 characters'));
      expect(msg('bad_venue:letters'), contains("venue's name"));
      expect(msg('bad_venue:contact'), contains('no links'));
      expect(msg('bad_venue:inappropriate'), contains('appropriate'));
    });

    test('the daily request limit says how many are allowed', () {
      expect(
        msg('daily_limit: you can post up to 3 match requests for the same day'),
        'You can post up to 3 match requests for the same day.',
      );
    });

    test('rate limits read as a plain request to slow down', () {
      for (final m in [
        'rate_limited: too many venue changes, try again later',
        'rate_limited: too many reports, try again later',
        'rate_limited: too many match requests, try again later',
      ]) {
        expect(msg(m), contains('too often'));
        expect(msg(m), isNot(contains('rate_limited')));
      }
    });

    test('other server messages are shown without the technical tail', () {
      for (final m in [
        'This match can no longer be changed',
        'The match has already started',
        'You cannot report your own venue',
        'Only match participants can report the venue',
        'Only the captain who opened the request can change the venue',
        // Venue suggested on a proposal.
        'Only the captain who received the proposal can report its venue',
        'This proposal has already been resolved',
        'Proposal not found',
        'The venue name was changed in the meantime. Refresh the list.',
      ]) {
        expect(msg(m), m);
      }
      // Details / hint never leak either.
      expect(
        friendlyError(const PostgrestException(
          message: 'Match not found',
          code: 'P0001',
          details: 'some detail',
          hint: 'some hint',
        )),
        'Match not found',
      );
    });
  });
}
