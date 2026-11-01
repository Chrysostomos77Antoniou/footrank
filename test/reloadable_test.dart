// Reloadable is what keeps the Matches tabs steady: a refresh keeps the old
// list on screen until the new one arrives, a failure never wipes what is
// already there, and a slow answer for something that is no longer selected
// (another team, an older filter) can never overwrite the current one.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/utils/reloadable.dart';

void main() {
  group('Reloadable', () {
    test('starts with nothing: no answer, no error, not loading', () {
      final r = Reloadable<List<int>>();
      expect(r.data, isNull);
      expect(r.error, isNull);
      expect(r.isLoading, isFalse);
      expect(r.hasFailed, isFalse);
    });

    test('tells the screen when loading starts and when the answer lands',
        () async {
      final r = Reloadable<int>();
      final seen = <({bool loading, int? data})>[];
      await r.reload(() async => 7, () {
        seen.add((loading: r.isLoading, data: r.data));
      });

      expect(seen, [
        (loading: true, data: null),
        (loading: false, data: 7),
      ]);
      expect(r.data, 7);
      expect(r.hasFailed, isFalse);
    });

    test('a refresh keeps the previous answer while the new one is on its way',
        () async {
      final r = Reloadable<String>();
      await r.reload(() async => 'first', () {});

      final slow = Completer<String>();
      final pending = r.reload(() => slow.future, () {});
      expect(r.isLoading, isTrue);
      expect(r.data, 'first', reason: 'the screen must not go blank');

      slow.complete('second');
      await pending;
      expect(r.data, 'second');
      expect(r.isLoading, isFalse);
    });

    test('a failure is kept, and the previous answer stays', () async {
      final r = Reloadable<String>();
      await r.reload(() async => 'first', () {});
      await r.reload(() => Future<String>.error(StateError('offline')), () {});

      expect(r.hasFailed, isTrue);
      expect(r.error, isA<StateError>());
      expect(r.data, 'first');
      expect(r.isLoading, isFalse);
    });

    test('a failure with nothing to show yet is still just a failure, not a '
        'throw', () async {
      final r = Reloadable<String>();
      await r.reload(() => Future<String>.error(StateError('offline')), () {});
      expect(r.data, isNull);
      expect(r.hasFailed, isTrue);
    });

    test('it has not "failed" while a retry is in flight', () async {
      final r = Reloadable<int>();
      await r.reload(() => Future<int>.error(StateError('offline')), () {});
      expect(r.hasFailed, isTrue);

      final slow = Completer<int>();
      final retry = r.reload(() => slow.future, () {});
      expect(r.hasFailed, isFalse);
      expect(r.isLoading, isTrue);

      slow.complete(1);
      await retry;
      expect(r.error, isNull, reason: 'a success clears the error');
      expect(r.data, 1);
    });

    test('an answer that arrives after a newer request is dropped', () async {
      final r = Reloadable<String>();
      final old = Completer<String>();
      final first = r.reload(() => old.future, () {});
      await r.reload(() async => 'new', () {});
      expect(r.data, 'new');

      old.complete('old');
      await first;
      expect(r.data, 'new', reason: 'the slow, older reply must not win');
      expect(r.isLoading, isFalse);
    });

    test('a failure of an older request is dropped too', () async {
      final r = Reloadable<String>();
      final old = Completer<String>();
      final first = r.reload(() => old.future, () {});
      await r.reload(() async => 'new', () {});

      old.completeError(StateError('late failure'));
      await first;
      expect(r.error, isNull);
      expect(r.data, 'new');
    });

    test('clear() forgets everything and drops the reply still on its way',
        () async {
      final r = Reloadable<String>();
      await r.reload(() async => 'team one', () {});

      final slow = Completer<String>();
      final pending = r.reload(() => slow.future, () {});
      r.clear();
      expect(r.data, isNull);
      expect(r.isLoading, isFalse);

      slow.complete('team one, late');
      await pending;
      expect(r.data, isNull,
          reason: 'the answer belonged to what was selected before');
      expect(r.error, isNull);
    });

    test('after clear() a new request works as usual', () async {
      final r = Reloadable<int>();
      await r.reload(() async => 1, () {});
      r.clear();
      await r.reload(() async => 2, () {});
      expect(r.data, 2);
    });
  });
}
